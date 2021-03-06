package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	BackendPipelineLayoutResource :: struct {
		vk_programs_descriptor_set_layout: vk.DescriptorSetLayout,
		vk_pipeline_layout:                vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_reflect_pipeline_layout :: proc(
		p_layout: ^PipelineLayoutResource,
		p_pipeline_layout_desc: PipelineLayoutDesc,
	) -> bool {

		assert(p_pipeline_layout_desc.layout_type != .GRAPHICS_MATERIAL) // @TODO Implement
		defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

		vert_shader := get_shader(p_pipeline_layout_desc.vert_shader_ref)
		frag_shader := get_shader(p_pipeline_layout_desc.frag_shader_ref)

		vk_bindings := make(
			[]vk.DescriptorSetLayoutBinding,
			len(vert_shader.desc_bindings) + len(frag_shader.desc_bindings),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)

		backend_add_shader_bindings(&vert_shader.desc_bindings, {.VERTEX}, 0, vk_bindings)

		backend_add_shader_bindings(
			&frag_shader.desc_bindings,
			{.FRAGMENT},
			u32(len(vert_shader.desc_bindings)),
			vk_bindings,
		)

		// Create programs descriptor set layout
		{
			create_info := vk.DescriptorSetLayoutCreateInfo {
				sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
				bindingCount = u32(len(vk_bindings)),
				pBindings    = raw_data(vk_bindings),
			}

			if vk.CreateDescriptorSetLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_layout.vk_programs_descriptor_set_layout,
			   ) != .SUCCESS {
				log.warn("Failed to create descriptor set layout")
				return false
			}
		}


		// Create pipeline layout
		{
			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = &p_layout.vk_programs_descriptor_set_layout,
				setLayoutCount = 1,
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
	@(private = "file")
	backend_add_shader_bindings :: proc(
		p_bindings: ^[]VulkanShaderBinding,
		p_stage_flags: vk.ShaderStageFlags,
		p_bindings_count: u32,
		p_out_vk_bindings: []vk.DescriptorSetLayoutBinding,
	) {

		curr_binding := p_bindings_count
		for binding in p_bindings {

			desc_binding := &p_out_vk_bindings[curr_binding]

			desc_binding.binding = binding.binding
			desc_binding.descriptorType = binding.type
			desc_binding.descriptorCount = binding.count
			// @TODO When Immutable samplers are added
			//desc_binding.pImmutableSamplers
			desc_binding.stageFlags = p_stage_flags
			curr_binding += 1
		}
	}

	//---------------------------------------------------------------------------//

}
