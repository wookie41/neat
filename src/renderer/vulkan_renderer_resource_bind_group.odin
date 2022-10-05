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
		descriptor_pool:                vk.DescriptorPool,
		descriptor_layouts_cache:       map[u32]vk.DescriptorSetLayout,
		samplers_descriptor_set_layout: vk.DescriptorSetLayout,
		samplers_descriptor_set:        vk.DescriptorSet,
		immutable_sampler:              []vk.Sampler,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupResource :: struct {
		vk_descriptor_set: vk.DescriptorSet,
	}

	//---------------------------------------------------------------------------//

	backend_init_bind_groups :: proc() -> bool {

		// Create descriptor pools
		{
			pool_sizes := []vk.DescriptorPoolSize{
				{type = .SAMPLER, descriptorCount = 1 << 15},
				{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1 << 15},
				{type = .SAMPLED_IMAGE, descriptorCount = 1 << 15},
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

		// Create samplers
		{
			INTERNAL.immutable_sampler = make(
				[]vk.Sampler,
				len(SamplerType),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			sampler_create_info := vk.SamplerCreateInfo {
				sType        = .SAMPLER_CREATE_INFO,
				magFilter    = .NEAREST,
				minFilter    = .NEAREST,
				addressModeU = .CLAMP_TO_EDGE,
				addressModeV = .CLAMP_TO_EDGE,
				addressModeW = .CLAMP_TO_EDGE,
				// @TODO
				// anisotropyEnable = true,
				//maxAnisotropy    = device_properties.limits.maxSamplerAnisotropy,
				borderColor  = .INT_OPAQUE_BLACK,
				compareOp    = .ALWAYS,
				mipmapMode   = .LINEAR,
			}

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[0],
			)

			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[1],
			)

			sampler_create_info.addressModeU = .REPEAT
			sampler_create_info.addressModeV = .REPEAT
			sampler_create_info.addressModeW = .REPEAT

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[2],
			)

			sampler_create_info.magFilter = .LINEAR
			sampler_create_info.minFilter = .LINEAR

			sampler_create_info.addressModeU = .CLAMP_TO_EDGE
			sampler_create_info.addressModeV = .CLAMP_TO_EDGE
			sampler_create_info.addressModeW = .CLAMP_TO_EDGE

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[3],
			)

			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[4],
			)

			sampler_create_info.addressModeU = .REPEAT
			sampler_create_info.addressModeV = .REPEAT
			sampler_create_info.addressModeW = .REPEAT

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_sampler[5],
			)
		}

		// Create samplers descriptor set
		{
			samplers_descriptor_set_bindings := []vk.DescriptorSetLayoutBinding{
				{
					binding = 0,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = INTERNAL.immutable_sampler,
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 1,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = INTERNAL.immutable_sampler,
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 2,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = INTERNAL.immutable_sampler,
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 3,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = INTERNAL.immutable_sampler,
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 4,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = INTERNAL.immutable_sampler,
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
			}

			descriptor_set_layout_create_info := vk.DescriptorSetLayoutCreateInfo {
				sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
				bindingCount = u32(len(samplers_descriptor_set_bindings)),
				pBindings    = raw_data(samplers_descriptor_set_bindings),
			}

			if vk.CreateDescriptorSetLayout(
				   G_RENDERER.device,
				   &descriptor_set_layout_create_info,
				   nil,
				   &INTERNAL.samplers_descriptor_set_layout,
			   ) != .SUCCESS {

				// @TODO We should delete stuff from INTERNAL here, 
				// but we're still gonna shut down the renderer, so screw it for now
				return false
			}

			allocate_info := vk.DescriptorSetAllocateInfo {
				sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
				pSetLayouts        = &INTERNAL.descriptor_layouts_cache,
				descriptorPool     = INTERNAL.descriptor_pool,
				descriptorSetCount = 1,
			}

			if vk.AllocateDescriptorSets(
				   G_RENDERER.device,
				   &allocate_info,
				   INTERNAL.samplers_descriptor_set,
			   ) != .SUCCESS {
				// @TODO We should delete stuff from INTERNAL here, 
				// but we're still gonna shut down the renderer, so screw it for now
				return false
			}
		}
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
				descriptor_set_layouts[layout_idx] = INTERNAL.descriptor_layouts_cache[bind_group_hash]
				continue
			}

			// Otherwise create a new one
			{
				bindings := make(
					[]vk.DescriptorSetLayoutBinding,
					len(bind_group.desc.textures) + len(bind_group.desc.buffers),
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
				defer delete(bindings, G_RENDERER_ALLOCATORS.temp_allocator)

				binding_idx := 0

				// Texture bindings
				for texture_binding in bind_group.desc.textures {
					bindings[binding_idx].binding = texture_binding.slot

					if .SampledImage in texture_binding.flags {
						bindings[binding_idx].descriptorType = .SAMPLED_IMAGE
					} else if .StorageImage in texture_binding.flags {
						bindings[binding_idx].descriptorType = .STORAGE_IMAGE
					} else {
						assert(false) // Probably added a new flag bit and forgot to handle it here
					}

					bindings[binding_idx].binding = texture_binding.slot
					bindings[binding_idx].descriptorCount = texture_binding.count
					binding_idx += 1
				}

				// Buffer bindings
				for texture_binding in bind_group.desc.textures {
					bindings[binding_idx].binding = texture_binding.slot

					if .SampledImage in texture_binding.flags {
						bindings[binding_idx].descriptorType = .SAMPLED_IMAGE
					} else if .StorageImage in texture_binding.flags {
						bindings[binding_idx].descriptorType = .STORAGE_IMAGE
					} else {
						assert(false) // Probably added ad new flag bit and forgot to handle it here
					}

					bindings[binding_idx].binding = texture_binding.slot
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
					&descriptor_set_layouts[layout_idx],
				)
				assert(res == .SUCCESS) // @TODO
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
			u32(len(p_ref_array)),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)

		res := vk.AllocateDescriptorSets(
			G_RENDERER.device,
			descriptor_set_alloc_info,
			descriptor_sets,
		)
		assert(res == .SUCCESS) // @TODO

		for descriptor_set, i in descriptor_sets {
			bind_group := get_bind_group(p_ref_array[i])
			bind_group.vk_descriptor_set = descriptor_set
		}
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
			len(p_bind_group.textures) + len(p_bind_group.buffers),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer free(hash_entries)

		entry_idx := 0

		for texture_binding in p_bind_group.desc.textures {
			if .SampledImage in texture_binding.flags {
				hash_entries[entry_idx].type = 0
			} else if .StorageImage in texture_binding.flags {
				hash_entries[entry_idx].type = 1
			} else {
				assert(false) // Probably added ad new flag bit and forgot to handle it here
			}
			hash_entries[entry_idx].slot = texture_binding.slot
			hash_entries[entry_idx].count = texture_binding.count
			entry_idx += 1
		}

		for buffer_binding in p_bind_group.desc.buffers {
			if .UniformBuffer in buffer_binding.flags {
				hash_entries[entry_idx].type = 2
			} else if .DynamicUniformBuffer in buffer_binding.flags {
				hash_entries[entry_idx].type = 3
			} else if .StorageBuffer in buffer_binding.flags {
				hash_entries[entry_idx].type = 4
			} else if .DynamicStorageBuffer in buffer_binding.flags {
				hash_entries[entry_idx].type = 5
			} else {
				assert(false) // Probably added ad new flag bit and forgot to handle it here
			}

			hash_entries[entry_idx].slot = buffer_binding.slot
			hash_entries[entry_idx].count = 1
			entry_idx += 1
		}

		return hash.adler32(mem.slice_to_bytes(hash_entries))
	}

	//---------------------------------------------------------------------------//

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_bind_groups :: proc(
		p_cmd_buff: CommandBufferRef,
		p_pipeline_type: PipelineType,
		p_pipeline_layout_ref: PipelineLayoutRef,
		p_bindings: []BindGroupBinding,
		p_samplers_bind_group_target: i32,
	) {
		cmd_buff := get_command_buffer(p_cmd_buff_ref)
		pipeline_layout := get_pipeline_layout(p_pipeline_layout_ref)
		pipeline_bind_point := map_pipeline_bind_point(p_pipeline_type)

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
		defer delete(dynamic_offsets)
		{
			dyn_offset_idx := 0
			for binding in p_bindings {
				for dynamic_offset in binding.dynamic_offsets {
					dynamic_offset[dyn_offset_idx] = dynamic_offset
					dyn_offset_idx += 1
				}
			}
		}

		descriptor_sets_count := u32(len(p_bindings))
		if p_samplers_bind_group_target >= 0 {
			descriptor_sets_count += 1
		}

		descriptor_sets := make(
			[]vk.DescriptorSet,
			descriptor_sets_count,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)


		// Fill descriptors sets array with the descriptor sets from the bind groups
		{
			bind_group_idx := 0
			for i in 0 ..< descriptor_sets_count {
				if i == p_samplers_bind_group_target {
					continue
				}
				bind_group := get_bind_group(p_bindings[bind_group_idx].bind_group_ref)
				descriptor_sets[i] = bind_group.vk_descriptor_set
				bind_group_idx += 1
			}
		}

		vk.CmdBindDescriptorSets(
			cmd_buff.vk_cmd_buff,
			pipeline_bind_point,
			pipeline_layout.vk_pipeline_layout,
			0,
			descriptor_sets_count,
			&descriptor_sets,
			dynamic_offsets_count,
			&dynamic_offsets,
		)
	}

	@(private = "file")
	map_pipeline_bind_point :: proc(p_pipeline_type: PipelineType) -> vk.PipelineBindPoint {
		if p_pipeline_type == .Graphics {
			return .GRAPHICS
		} else if p_pipeline_type.Compute {
			return .COMPUTE
		} else if p_pipeline_type.Raytracing {
			assert(false)
		} else {
			assert(false)
		}

	}

	//---------------------------------------------------------------------------//

}
