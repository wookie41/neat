package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import "core:slice"

	import vk "vendor:vulkan"

	import "../common"

	//---------------------------------------------------------------------------//

	NUM_DESCRIPTOR_SET_LAYOUTS :: u32(3)

	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		vk_pipeline_layout: vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_pipeline_layout :: proc(p_pipeline_layout: ^PipelineLayoutResource) -> bool {

		// @TODO support for compute shaders
		vert_shader := get_shader(p_pipeline_layout.desc.vert_shader_ref)
		frag_shader := get_shader(p_pipeline_layout.desc.frag_shader_ref)

		// Determine the number of distinct descriptor sets used across stages
		num_descriptor_sets_used := 0
		for descriptor_set in frag_shader.vk_descriptor_sets {
			num_descriptor_sets_used += 1
		}

		for descriptor_set in frag_shader.vk_descriptor_sets {
			for vert_descriptor_set in vert_shader.vk_descriptor_sets {
				if descriptor_set.set == vert_descriptor_set.set {
					break
				}
				num_descriptor_sets_used += 1
			}
		}

		bindings_per_set := make(
			map[u8][dynamic]vk.DescriptorSetLayoutBinding,
			num_descriptor_sets_used,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer {
			for set, bindings in bindings_per_set {
				delete(bindings)
			}
			delete(bindings_per_set)
		}

		texture_name_by_slot := make(map[u32]common.Name, 32, G_RENDERER_ALLOCATORS.temp_allocator)
		defer delete(texture_name_by_slot)

		// Gather vertex shader descriptor info
		for descriptor_set in &vert_shader.vk_descriptor_sets {

			// Skip bindless array
			if descriptor_set.set == 2 {
				continue
			}

			set_number := descriptor_set.set
			if (set_number in bindings_per_set) == false {
				bindings_per_set[set_number] = make(
					[dynamic]vk.DescriptorSetLayoutBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
			}

			set_bindings := &bindings_per_set[set_number]

			for descriptor in descriptor_set.descriptors {
				layout_binding := vk.DescriptorSetLayoutBinding {
					binding = descriptor.binding,
					descriptorCount = descriptor.count,
					descriptorType = descriptor.type,
					stageFlags = {.VERTEX},
					pImmutableSamplers = raw_data(VK_BINDLESS.immutable_samplers),
				}
				if descriptor.type == .SAMPLED_IMAGE || descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}

		}

		// Gather fragment shader descriptor info
		for descriptor_set in frag_shader.vk_descriptor_sets {

			// Skip bindless array
			if descriptor_set.set == 2 {
				continue
			}

			set_number := descriptor_set.set
			if (set_number in bindings_per_set) == false {
				bindings_per_set[set_number] = make(
					[dynamic]vk.DescriptorSetLayoutBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
			}

			set_bindings := &bindings_per_set[set_number]

			for descriptor in descriptor_set.descriptors {
				// Check if the vertex shader already added it, and if so, simply add the fragment stage
				already_used_by_vertex := false
				for existing_binding in set_bindings {
					if existing_binding.binding == descriptor.binding {
						existing_binding.stageFlags += {.FRAGMENT}
						assert(existing_binding.descriptorType == descriptor.type)
						already_used_by_vertex = true
						break
					}
				}

				if already_used_by_vertex {
					continue
				}

				layout_binding := vk.DescriptorSetLayoutBinding {
					binding = descriptor.binding,
					descriptorCount = descriptor.count,
					descriptorType = descriptor.type,
					stageFlags = {.FRAGMENT},
				}
				if descriptor.type == .SAMPLED_IMAGE || descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}
		}


		// Create the descriptor set layouts
		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			NUM_DESCRIPTOR_SET_LAYOUTS,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)

		descriptor_set_layouts[0] = vk.DescriptorSetLayout(0)
		descriptor_set_layouts[1] = vk.DescriptorSetLayout(0)


		if .UsesBindlessArray in vert_shader.flags || .UsesBindlessArray in frag_shader.flags {
			descriptor_set_layouts[2] = VK_BINDLESS.bindless_descriptor_set_layout
		} else {
			descriptor_set_layouts[2] = vk.DescriptorSetLayout(0)

		}

		defer {
			for descriptor_set_layout in descriptor_set_layouts {
				if descriptor_set_layout != vk.DescriptorSetLayout(0) &&
				   descriptor_set_layout != VK_BINDLESS.bindless_descriptor_set_layout {
					vk.DestroyDescriptorSetLayout(G_RENDERER.device, descriptor_set_layout, nil)
				}
			}
			delete(descriptor_set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)
		}

		// Create the descriptor set layout and the bind groups
		{
			p_pipeline_layout.bind_group_refs = make(
				[]BindGroupRef,
				len(bindings_per_set),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			for i in 0 ..< len(p_pipeline_layout.bind_group_refs) {
				p_pipeline_layout.bind_group_refs[i] = allocate_bind_group_ref(
					p_pipeline_layout.desc.name,
				)
			}
			bind_group_idx := 0
			for set in bindings_per_set {

				// @TODO Cache and reuse descriptor set layouts

				// Descriptor set
				descriptor_set_bindings := bindings_per_set[set]
				create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = u32(len(descriptor_set_bindings)),
					pBindings    = raw_data(descriptor_set_bindings),
				}

				if vk.CreateDescriptorSetLayout(
					   G_RENDERER.device,
					   &create_info,
					   nil,
					   &descriptor_set_layouts[set],
				   ) !=
				   .SUCCESS {
					log.warn("Failed to create descriptor set layout")
					return false
				}

				image_bindings := make([dynamic]ImageBinding, G_RENDERER_ALLOCATORS.temp_allocator)
				defer delete(image_bindings)

				buffer_bindings := make(
					[dynamic]BufferBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
				defer delete(buffer_bindings)

				for descriptor in descriptor_set_bindings {

					stage_flags: BindingUsageStageFlags
					if .VERTEX in descriptor.stageFlags {
						stage_flags += {.Vertex}
					}
					if .FRAGMENT in descriptor.stageFlags {
						stage_flags += {.Fragment}
					}
					if .COMPUTE in descriptor.stageFlags {
						stage_flags += {.Compute}
					}

					if descriptor.descriptorType == .SAMPLED_IMAGE {
						image_binding := ImageBinding {
							name        = texture_name_by_slot[descriptor.binding],
							count       = descriptor.descriptorCount,
							slot        = descriptor.binding,
							stage_flags = stage_flags,
							usage       = .SampledImage,
						}
						append(&image_bindings, image_binding)
					} else if descriptor.descriptorType == .STORAGE_IMAGE {
						image_binding := ImageBinding {
							name        = texture_name_by_slot[descriptor.binding],
							count       = descriptor.descriptorCount,
							slot        = descriptor.binding,
							stage_flags = stage_flags,
							usage       = .StorageImage,
						}
						append(&image_bindings, image_binding)
					} else if descriptor.descriptorType == .UNIFORM_BUFFER {
						buffer_binding := BufferBinding {
							slot         = descriptor.binding,
							stage_flags  = stage_flags,
							buffer_usage = .UniformBuffer,
						}
						append(&buffer_bindings, buffer_binding)
					} else if descriptor.descriptorType == .UNIFORM_BUFFER_DYNAMIC {
						buffer_binding := BufferBinding {
							slot         = descriptor.binding,
							stage_flags  = stage_flags,
							buffer_usage = .DynamicUniformBuffer,
						}
						append(&buffer_bindings, buffer_binding)
					} else if descriptor.descriptorType == .STORAGE_BUFFER {
						buffer_binding := BufferBinding {
							slot         = descriptor.binding,
							stage_flags  = stage_flags,
							buffer_usage = .StorageBuffer,
						}
						append(&buffer_bindings, buffer_binding)
					} else if descriptor.descriptorType == .STORAGE_BUFFER_DYNAMIC {
						buffer_binding := BufferBinding {
							slot         = descriptor.binding,
							stage_flags  = stage_flags,
							buffer_usage = .DynamicStorageBuffer,
						}
						append(&buffer_bindings, buffer_binding)
					} else if descriptor.descriptorType != .SAMPLER {
						assert(false, "Unsupported binding type")
					}
				}

				bind_group := get_bind_group(p_pipeline_layout.bind_group_refs[bind_group_idx])
				bind_group_idx += 1

				bind_group.desc.images = slice.clone(
					image_bindings[:],
					G_RENDERER_ALLOCATORS.resource_allocator,
				)
				bind_group.desc.buffers = slice.clone(
					buffer_bindings[:],
					G_RENDERER_ALLOCATORS.resource_allocator,
				)
			}
			create_bind_groups(p_pipeline_layout.bind_group_refs)
		}

		// Create pipeline layout
		{
			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = raw_data(descriptor_set_layouts),
				setLayoutCount = u32(len(descriptor_set_layouts)),
			}

			if vk.CreatePipelineLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_pipeline_layout.vk_pipeline_layout,
			   ) !=
			   .SUCCESS {
				log.warn("Failed to create pipeline layout")
				return false
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline_layout :: proc(p_pipeline_layout: ^PipelineLayoutResource) {
		vk.DestroyPipelineLayout(G_RENDERER.device, p_pipeline_layout.vk_pipeline_layout, nil)

	}

	//---------------------------------------------------------------------------//
}
