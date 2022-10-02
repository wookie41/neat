package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//


	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		vk_pipeline_layout:        vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_reflect_graphics_pipeline_layout :: proc(
		p_ref: PipelineLayoutRef,
		p_layout: ^PipelineLayoutResource,
	) -> bool {

		vert_shader := get_shader(p_layout.desc.vert_shader_ref)
		frag_shader := get_shader(p_layout.desc.frag_shader_ref)

		// Determine the number of distinct descriptor sets used across vertex and fragment shader
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
			map[uint][dynamic]vk.DescriptorSetLayoutBinding,
			num_descriptor_sets_used,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)

		defer {
			for _, bindings in bindings_per_set {
				delete(bindings)
			}
			delete(bindings_per_set)
		}

		// Gather vertex shader descriptor info
		for descriptor_set in vert_shader.vk_descriptor_sets {

			set_number := uint(descriptor_set.set)
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
				append(set_bindings, layout_binding)
			}
		}

		// Gather fragment shader descriptor info
		for descriptor_set in frag_shader.vk_descriptor_sets {

			set_number := uint(descriptor_set.set)
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
				append(set_bindings, layout_binding)
			}
		}

		// Create the descriptor set layouts
		descriptor_set_layout_create_info := make(
			[]vk.DescriptorSetLayoutCreateInfo,
			len(bindings_per_set),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_set_layout_create_info, G_RENDERER_ALLOCATORS.temp_allocator)

		p_layout.vk_descriptor_set_layouts = make(
			[]vk.DescriptorSetLayout,
			len(bindings_per_set),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		p_layout.vk_descriptor_set_numbers = make(
			[]u8,
			len(bindings_per_set),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		// Create the descriptor set layout
		{
			set_count := 0
			for set in bindings_per_set {
				descriptor_set_bindings := bindings_per_set[set]
				create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = u32(len(descriptor_set_bindings)),
					pBindings    = raw_data(descriptor_set_bindings),
				}

				p_layout.vk_descriptor_set_numbers[set_count] = u8(set)
				if vk.CreateDescriptorSetLayout(
					   G_RENDERER.device,
					   &create_info,
					   nil,
					   &p_layout.vk_descriptor_set_layouts[set_count],
				   ) != .SUCCESS {
					log.warn("Failed to create descriptor set layout")
					return false
				}
				set_count += 1
			}
		}

		// Create the descriptor sets
		{
			descriptor_sets_alloc_info := vk.DescriptorSetAllocateInfo {
				sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool     = G_RENDERER.vk_descriptor_pool,
				descriptorSetCount = u32(len(p_layout.vk_descriptor_set_layouts)),
				pSetLayouts        = raw_data(p_layout.vk_descriptor_set_layouts),
			}

			p_layout.vk_descriptor_sets = make(
				[]vk.DescriptorSet,
				descriptor_sets_alloc_info.descriptorSetCount,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			res := vk.AllocateDescriptorSets(
				G_RENDERER.device,
				&descriptor_sets_alloc_info,
				raw_data(p_layout.vk_descriptor_sets),
			)
			assert(res == .SUCCESS)
		}

		// Create pipeline layout
		{
			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = raw_data(p_layout.vk_descriptor_set_layouts),
				setLayoutCount = u32(len(p_layout.vk_descriptor_set_layouts)),
			}

			if vk.CreatePipelineLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_layout.vk_pipeline_layout,
			   ) != .SUCCESS {
				log.warn("Failed to create pipeline layout")
				return false
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
		pipeline_layout := get_pipeline_layout(p_ref)
		vk.FreeDescriptorSets(
			G_RENDERER.device,
			G_RENDERER.vk_descriptor_pool,
			u32(len(pipeline_layout.vk_descriptor_sets)),
			raw_data(pipeline_layout.vk_descriptor_sets),
		)
		for descriptor_set_layout in pipeline_layout.vk_descriptor_set_layouts {
			vk.DestroyDescriptorSetLayout(G_RENDERER.device, descriptor_set_layout, nil)
		}
		vk.DestroyPipelineLayout(G_RENDERER.device, pipeline_layout.vk_pipeline_layout, nil)
		delete(
			pipeline_layout.vk_descriptor_set_numbers,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		delete(
			pipeline_layout.vk_descriptor_set_layouts,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		delete(pipeline_layout.vk_descriptor_sets, G_RENDERER_ALLOCATORS.resource_allocator)

	}

	//---------------------------------------------------------------------------//
}
