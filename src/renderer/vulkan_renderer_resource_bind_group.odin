package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_pool:      vk.DescriptorPool,
		empty_descriptor_set: vk.DescriptorSet,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupResource :: struct {
		vk_descriptor_set: vk.DescriptorSet,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_bind_groups :: proc() -> bool {
		// Create descriptor pools
		{
			pool_sizes := []vk.DescriptorPoolSize{
				{type = .STORAGE_IMAGE, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
			}

			descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
				sType         = .DESCRIPTOR_POOL_CREATE_INFO,
				maxSets       = 1 << 15,
				poolSizeCount = u32(len(pool_sizes)),
				pPoolSizes    = raw_data(pool_sizes),
			}

			vk.CreateDescriptorPool(
				G_RENDERER.device,
				&descriptor_pool_create_info,
				nil,
				&INTERNAL.descriptor_pool,
			)
		}

		// Create an empty descriptor set
		{
			alloc_info := vk.DescriptorSetAllocateInfo {
				sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool     = INTERNAL.descriptor_pool,
				descriptorSetCount = 1,
				pSetLayouts        = &G_RENDERER.empty_descriptor_set_layout,
			}
			if vk.AllocateDescriptorSets(
				   G_RENDERER.device,
				   &alloc_info,
				   &INTERNAL.empty_descriptor_set,
			   ) !=
			   .SUCCESS {

				// @TODO Free the allocated pool 
				return false
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	backend_create_bind_groups :: proc(
		p_pipeline_layout_ref: PipelineLayoutRef,
		p_pipeline_layout: ^PipelineLayoutResource,
		out_bind_group_refs: []BindGroupRef,
	) -> bool {

		descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pSetLayouts        = &p_pipeline_layout.descriptor_set_layouts[0],
			descriptorSetCount = u32(len(p_pipeline_layout.descriptor_set_layouts)),
			descriptorPool     = INTERNAL.descriptor_pool,
		}
		descriptor_sets := make(
			[]vk.DescriptorSet,
			descriptor_set_alloc_info.descriptorSetCount,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)

		res := vk.AllocateDescriptorSets(
			G_RENDERER.device,
			&descriptor_set_alloc_info,
			raw_data(descriptor_sets),
		)
		assert(res == .SUCCESS) // @TODO

		for descriptor_set, i in descriptor_sets {
			bind_group := get_bind_group(out_bind_group_refs[i])
			bind_group.vk_descriptor_set = descriptor_set
		}

		return true
	}

	//---------------------------------------------------------------------------//

	backend_create_bind_group :: proc(
		p_pipeline_layout_ref: PipelineLayoutRef,
		p_pipeline_layout: ^PipelineLayoutResource,
		p_bind_group_idx: u32,
		out_bind_group: ^BindGroupResource,
	) -> bool {

		descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pSetLayouts        = &p_pipeline_layout.descriptor_set_layouts[p_bind_group_idx],
			descriptorSetCount = 1,
			descriptorPool     = INTERNAL.descriptor_pool,
		}

		return(
			vk.AllocateDescriptorSets(
				G_RENDERER.device,
				&descriptor_set_alloc_info,
				&out_bind_group.vk_descriptor_set,
			) ==
			.SUCCESS \
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_bind_groups :: proc(
		p_cmd_buff: ^CommandBufferResource,
		p_pipeline: ^PipelineResource,
		p_bindings: []BindGroupBinding,
	) {
		dynamic_offsets_count := 0

		// Determine the number of dynamic offsets
		for binding in p_bindings {
			dynamic_offsets_count += len(binding.dynamic_offsets)
		}

		// Create a joint dynamic offsets array
		dynamic_offsets := make([]u32, dynamic_offsets_count, G_RENDERER_ALLOCATORS.temp_allocator)
		defer delete(dynamic_offsets, G_RENDERER_ALLOCATORS.temp_allocator)

		{
			dyn_offset_idx := 0
			for binding in p_bindings {
				for dynamic_offset in binding.dynamic_offsets {
					dynamic_offsets[dyn_offset_idx] = dynamic_offset
					dyn_offset_idx += 1
				}
			}
		}

		descriptor_sets_count := u32(len(p_bindings))
		descriptor_sets := make(
			[]vk.DescriptorSet,
			descriptor_sets_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)

		// Fill descriptors sets array with the descriptor sets from the bind groups
		{
			for binding, i in p_bindings {
				if binding.bind_group_ref == InvalidBindGroupRef {
					descriptor_sets[i] = INTERNAL.empty_descriptor_set
					continue

				}
				bind_group := get_bind_group(binding.bind_group_ref)
				descriptor_sets[i] = bind_group.vk_descriptor_set
			}
		}

		pipeline_layout := get_pipeline_layout(p_pipeline.pipeline_layout_ref)
		pipeline_bind_point := map_pipeline_bind_point(pipeline_layout.desc.layout_type)

		vk.CmdBindDescriptorSets(
			p_cmd_buff.vk_cmd_buff,
			pipeline_bind_point,
			pipeline_layout.vk_pipeline_layout,
			0,
			descriptor_sets_count,
			raw_data(descriptor_sets),
			u32(dynamic_offsets_count),
			raw_data(dynamic_offsets),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_bind_groups :: proc(p_ref_array: []BindGroupRef) {

		descriptor_sets_to_free := make(
			[]vk.DescriptorSet,
			len(p_ref_array),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_sets_to_free, G_RENDERER_ALLOCATORS.temp_allocator)

		vk.FreeDescriptorSets(
			G_RENDERER.device,
			INTERNAL.descriptor_pool,
			u32(len(descriptor_sets_to_free)),
			raw_data(descriptor_sets_to_free),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_update_bind_groups :: proc(p_updates: []BindGroupUpdate) {

		// Allocate descriptor write array (for now we just write the entire bind group, no dirty bindings checking)
		images_infos_count := 0
		buffer_infos_count := 0

		for update in p_updates {
			images_infos_count += len(update.image_updates)
			buffer_infos_count += len(update.buffer_updates)
		}
		total_writes_count := buffer_infos_count + images_infos_count

		descriptor_writes := make(
			[]vk.WriteDescriptorSet,
			total_writes_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_writes, G_RENDERER_ALLOCATORS.temp_allocator)

		image_writes := make(
			[]vk.DescriptorImageInfo,
			images_infos_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(image_writes, G_RENDERER_ALLOCATORS.temp_allocator)

		buffer_writes := make(
			[]vk.DescriptorBufferInfo,
			buffer_infos_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(buffer_writes, G_RENDERER_ALLOCATORS.temp_allocator)

		write_idx := 0
		image_info_idx := 0
		buffer_info_idx := 0

		for _, i in p_updates {
			update := &p_updates[i]
			bind_group := get_bind_group(update.bind_group_ref)

			for buffer_update in &update.buffer_updates {
				buffer := get_buffer(buffer_update.buffer)
				buffer_writes[buffer_info_idx].buffer = buffer.vk_buffer
				buffer_writes[buffer_info_idx].offset = vk.DeviceSize(buffer_update.offset)
				buffer_writes[buffer_info_idx].range = vk.DeviceSize(buffer_update.size)

				descriptor_writes[write_idx].sType = .WRITE_DESCRIPTOR_SET
				descriptor_writes[write_idx].descriptorCount = 1
				descriptor_writes[write_idx].dstBinding = buffer_update.slot
				descriptor_writes[write_idx].dstSet = bind_group.vk_descriptor_set
				descriptor_writes[write_idx].pBufferInfo = &buffer_writes[buffer_info_idx]

				if .UniformBuffer in buffer.desc.usage {
					descriptor_writes[write_idx].descriptorType = .UNIFORM_BUFFER
				} else if .DynamicUniformBuffer in buffer.desc.usage {
					descriptor_writes[write_idx].descriptorType = .UNIFORM_BUFFER_DYNAMIC
				} else if .StorageBuffer in buffer.desc.usage {
					descriptor_writes[write_idx].descriptorType = .STORAGE_BUFFER
				} else if .DynamicStorageBuffer in buffer.desc.usage {
					descriptor_writes[write_idx].descriptorType = .STORAGE_BUFFER_DYNAMIC
				} else {
					assert(false) // Probably added a new flag bit and forgot to handle it here
				}

				buffer_info_idx += 1
				write_idx += 1
			}

			for image_update in update.image_updates {
				image := get_image(image_update.image_ref)

				if .AddressSubresource in image_update.flags {
					image_writes[image_info_idx].imageView =
						image.per_mip_vk_view[image_update.mip]
				} else {
					image_writes[image_info_idx].imageView = image.all_mips_vk_view
				}

				image_writes[image_info_idx].imageView = image.per_mip_vk_view[image_update.mip]

				image_writes[image_info_idx].imageLayout =
					image.vk_layout_per_mip[image_update.mip]

				descriptor_writes[write_idx].sType = .WRITE_DESCRIPTOR_SET
				descriptor_writes[write_idx].descriptorCount = 1
				descriptor_writes[write_idx].dstBinding = image_update.slot
				descriptor_writes[write_idx].dstSet = bind_group.vk_descriptor_set
				descriptor_writes[write_idx].pImageInfo = &image_writes[image_info_idx]
				descriptor_writes[write_idx].descriptorType = .SAMPLED_IMAGE

				image_info_idx += 1
				write_idx += 1
			}
		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(len(descriptor_writes)),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}

	//---------------------------------------------------------------------------//

}
