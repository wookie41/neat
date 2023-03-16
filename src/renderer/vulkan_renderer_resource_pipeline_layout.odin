package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import "core:slice"

	import vk "vendor:vulkan"

	import "../common"
	//---------------------------------------------------------------------------//


	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		vk_pipeline_layout: vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_pipeline_layout :: proc(p_layout: ^PipelineLayoutResource) -> bool {

		vert_shader := get_shader(p_layout.desc.vert_shader_ref)
		frag_shader := get_shader(p_layout.desc.frag_shader_ref)

		// Determine the number of distinct descriptor sets used across 
		num_descriptor_sets_used := len(vert_shader.vk_descriptor_sets)
		for frag_descriptor_set in frag_shader.vk_descriptor_sets {
			for vert_descriptor_set in vert_shader.vk_descriptor_sets {
				if frag_descriptor_set.set == vert_descriptor_set.set {
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

		texture_name_by_slot := make(
			map[u32]common.Name,
			32,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(texture_name_by_slot)

		// Gather vertex shader descriptor info
		for descriptor_set in &vert_shader.vk_descriptor_sets {

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
				}
				if
				   descriptor.type == .SAMPLED_IMAGE ||
				   descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}

		}

		// Gather fragment shader descriptor info
		for descriptor_set in frag_shader.vk_descriptor_sets {

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
				if
				   descriptor.type == .SAMPLED_IMAGE ||
				   descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}
		}

		// Create the descriptor set layouts
		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			len(bindings_per_set),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer {
			for descriptor_set_layout in descriptor_set_layouts {
				vk.DestroyDescriptorSetLayout(
					G_RENDERER.device,
					descriptor_set_layout,
					nil,
				)
			}
			delete(descriptor_set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)
		}

		// Create the descriptor set layout and the bind groups
		{
			p_layout.bind_group_refs = make(
				[]BindGroupRef,
				len(bindings_per_set) - 1, // Set 0 is reserved for samplers and texture array
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			for i in 0 ..< len(p_layout.bind_group_refs) {
				p_layout.bind_group_refs[i] = allocate_bind_group_ref(p_layout.desc.name)
			}
			bind_group_idx := 0
			for set in bindings_per_set {

				// Descriptor set
				descriptor_set_bindings := bindings_per_set[set]
				create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = u32(len(descriptor_set_bindings)),
					pBindings    = raw_data(descriptor_set_bindings),
				}

				if
				   vk.CreateDescriptorSetLayout(
					   G_RENDERER.device,
					   &create_info,
					   nil,
					   &descriptor_set_layouts[set],
				   ) !=
				   .SUCCESS {
					log.warn("Failed to create descriptor set layout")
					return false
				}

				image_bindings := make(
					[dynamic]ImageBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
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

				// Set 0 is reserved for samplers and texture array
				if set != 0 {
					bind_group := get_bind_group(
						p_layout.bind_group_refs[bind_group_idx],
					)
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

			}
			create_bind_groups(p_layout.bind_group_refs)
		}

		// Create pipeline layout
		{
			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = raw_data(descriptor_set_layouts),
				setLayoutCount = u32(len(descriptor_set_layouts)),
			}

			if
			   vk.CreatePipelineLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_layout.vk_pipeline_layout,
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
		vk.DestroyPipelineLayout(
			G_RENDERER.device,
			p_pipeline_layout.vk_pipeline_layout,
			nil,
		)

	}

	//---------------------------------------------------------------------------//
}
