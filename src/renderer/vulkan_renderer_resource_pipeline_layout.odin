package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutUsedDescriptorsFlagBits :: enum u16 {
		VertexBindlessTextureArray,
		VertexSamplers,
		FragmentBindlessTextureArray,
		FragmentSamplers,
		VertexPerFrameUniform,
		VertexPerViewUniform,
		VertexPerRenderPassUniform,
		VertexPerInstanceUniform,
		FragmentPerFrameUniform,
		FragmentPerViewUniform,
		FragmentPerRenderPassUniform,
		FragmentPerInstanceUniform,
	}

	@(private)
	BackendPipelineLayoutUsedDescriptorsFlags :: distinct bit_set[BackendPipelineLayoutUsedDescriptorsFlagBits;u16]

	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		used_descriptors_flags:            BackendPipelineLayoutUsedDescriptorsFlags,
		vk_programs_descriptor_set_layout: vk.DescriptorSetLayout,
		vk_pipeline_layout:                vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_reflect_pipeline_layout :: proc(
		p_ref: PipelineLayoutRef,
		p_layout: ^PipelineLayoutResource,
	) -> bool {

		vert_shader := get_shader(p_layout.desc.vert_shader_ref)
		frag_shader := get_shader(p_layout.desc.frag_shader_ref)

		vk_bindings := make(
			[]vk.DescriptorSetLayoutBinding,
			len(vert_shader.vk_bindings) + len(frag_shader.vk_bindings),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(vk_bindings, G_RENDERER_ALLOCATORS.temp_allocator)

		// Determine which of the global descriptors are being used in the pipeline
		{
			// Vertex shader
			for binding in vert_shader.vk_bindings {
				// Set 0
				if binding.set == 0 {
					if binding.binding == 0 {
						p_layout.used_descriptors_flags += {.VertexBindlessTextureArray}
					} else if binding.binding == 1 {
						p_layout.used_descriptors_flags += {.VertexSamplers}

					}
				}
				// Set 1
				if binding.set == 1 {
					if binding.binding == 0 {
						p_layout.used_descriptors_flags += {.VertexPerFrameUniform}
					} else if binding.binding == 1 {
						p_layout.used_descriptors_flags += {.VertexPerViewUniform}
					} else if binding.binding == 2 {
						p_layout.used_descriptors_flags += {.VertexPerRenderPassUniform}
					}
				}
			}

		}

		backend_add_shader_bindings(&vert_shader.vk_bindings, {.VERTEX}, 0, vk_bindings)

		backend_add_shader_bindings(
			&frag_shader.vk_bindings,
			{.FRAGMENT},
			u32(len(vert_shader.vk_bindings)),
			vk_bindings,
		)

		// Create programs descriptor set layout
		{
			create_info := vk.DescriptorSetLayoutCreateInfo {
				sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
				bindingCount = u32(len(vk_bindings)),
				pBindings    = raw_data(vk_bindings),
			}

			if
			   vk.CreateDescriptorSetLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_layout.vk_programs_descriptor_set_layout,
			   ) !=
			   .SUCCESS {
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

	@(private)
	backend_destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
		// nothing to do
	}

	//---------------------------------------------------------------------------//
}
