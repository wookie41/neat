package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_pool: vk.DescriptorPool,
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
				{type = .SAMPLER, descriptorCount = len(SamplerType)},
				{type = .STORAGE_IMAGE, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
			}

			descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
				sType = .DESCRIPTOR_POOL_CREATE_INFO,
				maxSets = 1 << 15,
				poolSizeCount = u32(len(pool_sizes)),
				pPoolSizes = raw_data(pool_sizes),
				flags = {.UPDATE_AFTER_BIND}, // @TODO create a separate pool for that 
			}

			vk.CreateDescriptorPool(
				G_RENDERER.device,
				&descriptor_pool_create_info,
				nil,
				&INTERNAL.descriptor_pool,
			)
		}
		return true
	}

	//---------------------------------------------------------------------------//

	backend_create_bind_group :: proc(
		p_bind_group_ref: BindGroupRef,
		p_bind_group: ^BindGroupResource,
	) -> bool {

		bind_group_layout := get_bind_group_layout(p_bind_group.desc.layout_ref)

		descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pSetLayouts        = &bind_group_layout.vk_descriptor_set_layout,
			descriptorSetCount = 1,
			descriptorPool     = INTERNAL.descriptor_pool,
		}
		descriptor_sets := make([]vk.DescriptorSet, 1, G_RENDERER_ALLOCATORS.temp_allocator)
		defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)

		return(
			vk.AllocateDescriptorSets(
				G_RENDERER.device,
				&descriptor_set_alloc_info,
				&p_bind_group.vk_descriptor_set,
			) ==
			.SUCCESS \
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_bind_group :: proc(
		p_cmd_buff: ^CommandBufferResource,
		p_pipeline: ^PipelineResource,
		p_bind_group: ^BindGroupResource,
		p_target: u32,
		p_dynamic_offsets: []u32,
	) {
		vk.CmdBindDescriptorSets(
			p_cmd_buff.vk_cmd_buff,
			map_pipeline_bind_point(p_pipeline.type),
			p_pipeline.vk_pipeline_layout,
			p_target,
			1,
			&p_bind_group.vk_descriptor_set,
			u32(len(p_dynamic_offsets)),
			raw_data(p_dynamic_offsets),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_bind_group :: proc(p_bind_group_ref: BindGroupRef) {
		bind_group := get_bind_group(p_bind_group_ref)
		vk.FreeDescriptorSets(
			G_RENDERER.device,
			INTERNAL.descriptor_pool,
			1,
			&bind_group.vk_descriptor_set,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_update :: proc(
		p_bind_group_ref: BindGroupRef,
		p_bind_group_update: BindGroupUpdate,
	) {

		bind_group := get_bind_group(p_bind_group_ref)

		// Allocate descriptor write array (for now we just write the entire bind group, no dirty bindings checking)
		images_infos_count := len(p_bind_group_update.images)
		buffer_infos_count := len(p_bind_group_update.buffers)
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

		image_write_idx := 0
		buffer_write_idx := 0

		bind_group_layout := get_bind_group_layout(bind_group.desc.layout_ref)

		num_descriptor_writes: u32 = 0
		for binding in bind_group_layout.desc.bindings {

			if binding.type == .UniformBuffer ||
			   binding.type == .UniformBufferDynamic ||
			   binding.type == .StorageBuffer ||
			   binding.type == .StorageBufferDynamic {

				buffer_binding := p_bind_group_update.buffers[buffer_write_idx]

				if buffer_binding.buffer_ref == InvalidBufferRef {
					// Write null descriptor 
					buffer_write_idx += 1
					continue
				}

				buffer := get_buffer(buffer_binding.buffer_ref)

				buffer_writes[buffer_write_idx].buffer = buffer.vk_buffer
				buffer_writes[buffer_write_idx].offset = vk.DeviceSize(buffer_binding.offset)
				buffer_writes[buffer_write_idx].range = vk.DeviceSize(buffer_binding.size)

				descriptor_writes[num_descriptor_writes] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					dstBinding      = u32(num_descriptor_writes),
					dstSet          = bind_group.vk_descriptor_set,
					pBufferInfo     = &buffer_writes[buffer_write_idx],
				}

				if .UniformBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType = .UNIFORM_BUFFER
				} else if .DynamicUniformBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType =
					.UNIFORM_BUFFER_DYNAMIC
				} else if .StorageBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType = .STORAGE_BUFFER
				} else if .DynamicStorageBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType =
					.STORAGE_BUFFER_DYNAMIC
				} else {
					assert(false) // Unsupported descriptor type
				}

				num_descriptor_writes += 1
				buffer_write_idx += 1
				continue
			}

			if binding.type == .Image || binding.type == .StorageImage {

				image_binding := p_bind_group_update.images[image_write_idx]

				if image_binding.image_ref == InvalidImageRef {
					// Write null descriptor
					image_write_idx += 1
					continue
				}

				image := &g_resources.image_resources[get_image_idx(image_binding.image_ref)]

				if image_binding.mip > 0 {
					image_writes[image_write_idx].imageView =
						image.backend_image.per_mip_vk_view[image_binding.mip]
					image_writes[image_write_idx].imageLayout =
						image.backend_image.vk_layout_per_mip[image_binding.mip]

				} else {
					image_writes[image_write_idx].imageView = image.backend_image.all_mips_vk_view
					image_writes[image_write_idx].imageLayout = image.backend_image.vk_layout_per_mip[0]
				}

				descriptor_writes[num_descriptor_writes] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					dstBinding      = u32(num_descriptor_writes),
					dstSet          = bind_group.vk_descriptor_set,
					pImageInfo      = &image_writes[image_write_idx],
				}

				if binding.type == .Image {
					descriptor_writes[num_descriptor_writes].descriptorType = .SAMPLED_IMAGE
				} else {
					descriptor_writes[num_descriptor_writes].descriptorType = .STORAGE_IMAGE
				}

				image_write_idx += 1
				num_descriptor_writes += 1
				continue
			}
		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(num_descriptor_writes),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}

	//---------------------------------------------------------------------------//

}
