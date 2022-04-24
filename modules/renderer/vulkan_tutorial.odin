package renderer

import vk "vendor:vulkan"
import "core:fmt"

G_VT: struct {
	pipeline_layout:        vk.PipelineLayout,
	pso:                    vk.Pipeline,
	vertex_shader_module:   vk.ShaderModule,
	fragment_shader_module: vk.ShaderModule,
	command_pools:          [dynamic]vk.CommandPool,
	command_buffers:        [dynamic]vk.CommandBuffer,
}

init_vt :: proc() -> bool {

	{
		using G_RENDERER
		using G_VT

		// load the code
		vertex_shader_code := #load("app_data/assets/shaders/setup_sdl2_debug.vert.spv")
		fragment_shader_code := #load("app_data/assets/shaders/setup_sdl2_debug.frag.spv")

		// create the modules for each
		vertex_module_info := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = len(vertex_shader_code),
			pCode    = cast(^u32)raw_data(vertex_shader_code),
		}

		vk.CreateShaderModule(device, &vertex_module_info, nil, &vertex_shader_module)

		fragment_module_info := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = len(fragment_shader_code),
			pCode    = cast(^u32)raw_data(fragment_shader_code),
		}
		vk.CreateShaderModule(device, &fragment_module_info, nil, &fragment_shader_module)

		// create stage info for each
		vertex_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vertex_shader_module,
			pName = "main",
		}
		fragment_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = fragment_shader_module,
			pName = "main",
		}

		shader_stages := []vk.PipelineShaderStageCreateInfo{
			vertex_stage_info,
			fragment_stage_info,
		}

		// state for vertex input
		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		}

		// state for assembly
		input_assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
			sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology               = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		}
		// state for viewport
		viewport := vk.Viewport {
			x        = 0.0,
			y        = 0.0,
			width    = cast(f32)swap_extent.width,
			height   = cast(f32)swap_extent.height,
			minDepth = 0.0,
			maxDepth = 1.0,
		}

		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = swap_extent,
		}

		viewport_state := vk.PipelineViewportStateCreateInfo {
			sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			pViewports    = &viewport,
			scissorCount  = 1,
			pScissors     = &scissor,
		}

		// state for rasteriser
		rasteriser := vk.PipelineRasterizationStateCreateInfo {
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			lineWidth = 1.0,
			cullMode = {.BACK},
			frontFace = .CLOCKWISE,
			depthBiasEnable = false,
		}

		// state for multisampling
		multisampling := vk.PipelineMultisampleStateCreateInfo {
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			sampleShadingEnable = false,
			rasterizationSamples = {._1},
		}

		// state for colour blending
		colour_blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = true,
			srcColorBlendFactor = .ONE,
			dstColorBlendFactor = .ZERO,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp = .ADD,
		}

		colour_blending := vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &colour_blend_attachment,
			blendConstants = {0.0, 0.0, 0.0, 0.0},
		}

		// pipeline layout
		pipeline_layout_info := vk.PipelineLayoutCreateInfo {
			sType = .PIPELINE_LAYOUT_CREATE_INFO,
		}

		if vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, &pipeline_layout) != .SUCCESS {
			fmt.eprintln("couldn't create pipeline layout")
			return false
		}

		pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
			sType                   = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount    = 1,
			pColorAttachmentFormats = &surface_format.format,
		}

		pipeline_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			pNext               = &pipeline_rendering_create_info,
			stageCount          = u32(len(shader_stages)),
			pStages             = raw_data(shader_stages),
			pVertexInputState   = &vertex_input_info,
			pInputAssemblyState = &input_assembly_info,
			pViewportState      = &viewport_state,
			pRasterizationState = &rasteriser,
			pMultisampleState   = &multisampling,
			pColorBlendState    = &colour_blending,
			layout              = pipeline_layout,
		}

		if vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_info, nil, &pso) != .SUCCESS {
			fmt.eprintln("couldn't create graphics pipeline")
			return false
		}
	}

	{
		using G_RENDERER
		using G_VT

		pool_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			queueFamilyIndex = u32(queue_family_graphics_index),
		}

		resize(&command_pools, int(num_frames_in_flight))
		resize(&command_buffers, int(num_frames_in_flight))

		for i in 0 ..< num_frames_in_flight {
			if vk.CreateCommandPool(device, &pool_info, nil, &command_pools[i]) != .SUCCESS {
				fmt.eprintln("couldn't create command pool")
				return false
			}
			alloc_info := vk.CommandBufferAllocateInfo {
				sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool        = command_pools[i],
				level              = .PRIMARY,
				commandBufferCount = 1,
			}

			if vk.AllocateCommandBuffers(device, &alloc_info, &command_buffers[i]) != .SUCCESS {
				fmt.eprintln("couldn't allocate command buffers")
				return false
			}
		}
	}

	return true
}

deinit_vt :: proc() {
	using G_VT
	using G_RENDERER
	for cmd_pool in command_pools {
		vk.DestroyCommandPool(device, cmd_pool, nil)
	}
	vk.DestroyShaderModule(device, vertex_shader_module, nil)
	vk.DestroyShaderModule(device, fragment_shader_module, nil)
	vk.DestroyPipeline(device, pso, nil)
	vk.DestroyPipelineLayout(device, pipeline_layout, nil)
}
