package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"
import "core:hash"
import "core:mem"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_pool:          vk.DescriptorPool,
		descriptor_layouts_cache: map[u32]vk.DescriptorSetLayout,
		empty_descriptor_set:     vk.DescriptorSet,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupResource :: struct {
		vk_descriptor_set_layout: vk.DescriptorSetLayout,
		vk_descriptor_set:        vk.DescriptorSet,
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

		// Init the descripor set layouts cache
		{
			INTERNAL.descriptor_layouts_cache = make(
				map[u32]vk.DescriptorSetLayout,
				512,
				G_RENDERER_ALLOCATORS.resource_allocator,
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
			   ) != .SUCCESS {

				// @TODO Free the allocated pool 
				return false
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	backend_create_bind_groups :: proc(p_ref_array: []BindGroupRef) -> bool {
		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			len(p_ref_array),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)

		for ref, layout_idx in p_ref_array {
			bind_group := get_bind_group(ref)
			bind_group_hash := calculate_bind_group_hash(bind_group)

			// Use an existing layout if we have one
			if bind_group_hash in INTERNAL.descriptor_layouts_cache {
				bind_group.vk_descriptor_set_layout = INTERNAL.descriptor_layouts_cache[bind_group_hash]
				descriptor_set_layouts[layout_idx] = bind_group.vk_descriptor_set_layout
				continue
			}

			// Otherwise create a new one
			{
				bindings := make(
					[]vk.DescriptorSetLayoutBinding,
					len(bind_group.desc.images) + len(bind_group.desc.buffers),
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
				defer delete(bindings, G_RENDERER_ALLOCATORS.temp_allocator)


				binding_idx := 0

				// Image bindings
				for image_binding in bind_group.desc.images {
					bindings[binding_idx].binding = image_binding.slot

					if .SampledImage == image_binding.usage {
						bindings[binding_idx].descriptorType = .SAMPLED_IMAGE
					} else if .StorageImage == image_binding.usage {
						bindings[binding_idx].descriptorType = .STORAGE_IMAGE
					} else {
						assert(false) // Probably added a new flag bit and forgot to handle it here
					}

					bindings[binding_idx].binding = image_binding.slot
					bindings[binding_idx].descriptorCount = image_binding.count

					if .Vertex in image_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.VERTEX}
					}
					if .Fragment in image_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.FRAGMENT}
					}
					if .Compute in image_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.COMPUTE}
					}

					binding_idx += 1
				}

				// Buffer bindings
				for buffer_binding in bind_group.desc.buffers {
					if buffer_binding.buffer_usage == .UniformBuffer {
						bindings[binding_idx].descriptorType = .UNIFORM_BUFFER
					} else if buffer_binding.buffer_usage == .DynamicUniformBuffer {
						bindings[binding_idx].descriptorType = .UNIFORM_BUFFER_DYNAMIC
					} else if buffer_binding.buffer_usage == .StorageBuffer {
						bindings[binding_idx].descriptorType = .STORAGE_BUFFER
					} else if buffer_binding.buffer_usage == .DynamicStorageBuffer {
						bindings[binding_idx].descriptorType = .STORAGE_BUFFER_DYNAMIC
					} else {
						// Probably added ad new flag bit and forgot to handle it here or it's not a suported buffer type
						assert(false)
					}

					if .Vertex in buffer_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.VERTEX}
					}
					if .Fragment in buffer_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.FRAGMENT}
					}
					if .Compute in buffer_binding.stage_flags {
						bindings[binding_idx].stageFlags += {.COMPUTE}
					}

					bindings[binding_idx].binding = buffer_binding.slot
					bindings[binding_idx].descriptorCount = 1
					binding_idx += 1
				}

				create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					pBindings    = raw_data(bindings),
					bindingCount = u32(len(bindings)),
				}

				res := vk.CreateDescriptorSetLayout(
					G_RENDERER.device,
					&create_info,
					nil,
					&bind_group.vk_descriptor_set_layout,
				)
				assert(res == .SUCCESS) // @TODO

				descriptor_set_layouts[layout_idx] = bind_group.vk_descriptor_set_layout
			}
		}

		descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pSetLayouts        = raw_data(descriptor_set_layouts),
			descriptorSetCount = u32(len(descriptor_set_layouts)),
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
			bind_group := get_bind_group(p_ref_array[i])
			bind_group.vk_descriptor_set = descriptor_set
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	BindGroupHashEntry :: struct {
		type:  u32,
		slot:  u32,
		count: u32,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	calculate_bind_group_hash :: proc(p_bind_group: ^BindGroupResource) -> u32 {
		hash_entries := make(
			[]BindGroupHashEntry,
			len(p_bind_group.desc.images) + len(p_bind_group.desc.buffers),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(hash_entries, G_RENDERER_ALLOCATORS.temp_allocator)


		entry_idx := 0
		for image_binding in p_bind_group.desc.images {
			if image_binding.usage == .SampledImage {
				hash_entries[entry_idx].type = 0
			} else if image_binding.usage == .StorageImage {
				hash_entries[entry_idx].type = 1
			} else {
				assert(false) // Probably added ad new flag bit and forgot to handle it here
			}
			hash_entries[entry_idx].slot = image_binding.slot
			hash_entries[entry_idx].count = image_binding.count
			entry_idx += 1
		}

		for buffer_binding in p_bind_group.desc.buffers {
			if buffer_binding.buffer_usage == .UniformBuffer {
				hash_entries[entry_idx].type = 2
			} else if buffer_binding.buffer_usage == .DynamicUniformBuffer {
				hash_entries[entry_idx].type = 3
			} else if buffer_binding.buffer_usage == .StorageBuffer {
				hash_entries[entry_idx].type = 4
			} else if buffer_binding.buffer_usage == .DynamicStorageBuffer {
				hash_entries[entry_idx].type = 5
			} else {
				// Probably added ad new flag bit and forgot to handle it here or it's not a suported buffer type
				assert(false)
			}

			hash_entries[entry_idx].slot = buffer_binding.slot
			hash_entries[entry_idx].count = 1
			entry_idx += 1
		}

		return hash.adler32(mem.slice_to_bytes(hash_entries))
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
		dynamic_offsets := make(
			[]u32,
			dynamic_offsets_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
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

		for ref, i in p_ref_array {
			bind_group := get_bind_group(ref)
			descriptor_sets_to_free[i] = bind_group.vk_descriptor_set
			vk.DestroyDescriptorSetLayout(
				G_RENDERER.device,
				bind_group.vk_descriptor_set_layout,
				nil,
			)
		}

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
					image_writes[image_info_idx].imageView = image.per_mip_vk_view[image_update.mip]
				} else {
					image_writes[image_info_idx].imageView = image.all_mips_vk_view
				}

				image_writes[image_info_idx].imageView = image.per_mip_vk_view[image_update.mip]

				image_writes[image_info_idx].imageLayout = image.vk_layout_per_mip[image_update.mip]

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

	@(private)
	backend_clone_bind_groups :: proc(
		p_original_bind_group_refs: []BindGroupRef,
		p_cloned_bind_group_refs: []BindGroupRef,
	) -> bool {
		// @TODO handle descriptor layout cache
		set_layouts := make(
			[]vk.DescriptorSetLayout,
			len(p_cloned_bind_group_refs),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)

		descriptor_sets := make(
			[]vk.DescriptorSet,
			len(p_cloned_bind_group_refs),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)

		for i in 0 ..< len(p_original_bind_group_refs) {
			original_bind_group := get_bind_group(p_original_bind_group_refs[i])
			cloned_bind_group := get_bind_group(p_cloned_bind_group_refs[i])

			cloned_bind_group.vk_descriptor_set_layout = original_bind_group.vk_descriptor_set_layout

			set_layouts[i] = cloned_bind_group.vk_descriptor_set_layout
		}

		allocate_descriptor_set_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = INTERNAL.descriptor_pool,
			descriptorSetCount = u32(len(set_layouts)),
			pSetLayouts        = raw_data(set_layouts),
		}

		res := vk.AllocateDescriptorSets(
			G_RENDERER.device,
			&allocate_descriptor_set_info,
			raw_data(descriptor_sets),
		)
		assert(res == .SUCCESS) // @TODO

		for bind_group_ref, i in p_cloned_bind_group_refs {
			get_bind_group(bind_group_ref).vk_descriptor_set = descriptor_sets[i]
		}

		return true
	}
	//---------------------------------------------------------------------------//

}
