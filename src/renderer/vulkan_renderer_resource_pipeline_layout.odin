package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	VulkanDescriptorSetLayout :: struct {
		set:    u8,
		layout: vk.DescriptorSetLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		vk_descriptor_set_layouts: []VulkanDescriptorSetLayout,
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
		defer delete(bindings_per_set)

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
			[]VulkanDescriptorSetLayout,
			len(bindings_per_set),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		// Create the descriptor sets
		{
			set_count := 0
			for set in bindings_per_set {
				descriptor_set_bindings := bindings_per_set[set]
				create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = u32(len(descriptor_set_bindings)),
					pBindings    = raw_data(descriptor_set_bindings),
				}

				p_layout.vk_descriptor_set_layouts[set_count].set = u8(set)
				if vk.CreateDescriptorSetLayout(
					   G_RENDERER.device,
					   &create_info,
					   nil,
					   &p_layout.vk_descriptor_set_layouts[set_count].layout,
				   ) != .SUCCESS {
					log.warn("Failed to create descriptor set layout")
					return false
				}
				set_count += 1
			}
		}
		

		// Create pipeline layout
		{
			descriptor_set_layouts := make(
				[]vk.DescriptorSetLayout, 
				len(p_layout.vk_descriptor_set_layouts), 
				G_RENDERER_ALLOCATORS.temp_allocator)

			defer delete(descriptor_set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)

			for descriptor_set_layout, i in &p_layout.vk_descriptor_set_layouts {
				descriptor_set_layouts[i] = descriptor_set_layout.layout
			}

			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = raw_data(descriptor_set_layouts),
				setLayoutCount = u32(len(descriptor_set_layouts)),
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

		// Cleanup
		{
			for _, bindings in bindings_per_set {
				delete(bindings)
			}
			delete(bindings_per_set)
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
		pipeline_layout := get_pipeline_layout(p_ref)
		delete(
			pipeline_layout.vk_descriptor_set_layouts,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}

	//---------------------------------------------------------------------------//
}
