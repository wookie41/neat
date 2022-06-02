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

	backend_reflect_pipeline_layout :: proc(
		p_layout: ^PipelineLayoutResource,
		p_layout_type: PipelineType,
		p_vert_shader_ref: ShaderRef,
		p_frag_shader_ref: ShaderRef,
	) -> bool {

		assert(p_layout_type != .GRAPHICS_MATERIAL) // @TODO Implement

		vert_shader_idx := get_ref_idx(p_vert_shader_ref)
		frag_shader_idx := get_ref_idx(p_frag_shader_ref)

		vk_bindings := make(
			[]vk.DescriptorSetLayoutBinding,
			len(G_SHADER_RESOURCES[vert_shader_idx].desc_bindings) +
			len(G_SHADER_RESOURCES[frag_shader_idx].desc_bindings),
			G_RENDERER_ALLOCATORS.temp_arena_allocator,
		)
		defer delete(vk_bindings)

		backend_add_shader_bindings(
			&G_SHADER_RESOURCES[vert_shader_idx].desc_bindings,
			{.VERTEX},
			0,
			vk_bindings,
		)

		backend_add_shader_bindings(
			&G_SHADER_RESOURCES[frag_shader_idx].desc_bindings,
			{.FRAGMENT},
			u32(len(G_SHADER_RESOURCES[vert_shader_idx].desc_bindings)),
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
