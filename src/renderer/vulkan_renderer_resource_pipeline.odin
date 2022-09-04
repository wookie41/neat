package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"
	import os "core:os"
	import log "core:log"
	// import "core:math/linalg/glsl"

	//---------------------------------------------------------------------------//

	BackendPipelineResource :: struct {
		vk_pipeline: vk.Pipeline,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	VERTEX_BINDINGS_PER_TYPE := map[VertexLayout][]vk.VertexInputBindingDescription {
		.Mesh = {
		// {binding = 0, stride = size_of(glsl.vec3), inputRate = .VERTEX},
		// {binding = 1, stride = size_of(glsl.vec3), inputRate = .VERTEX},
		// {binding = 2, stride = size_of(glsl.vec2), inputRate = .VERTEX},
		{binding = 0, stride = size_of(MeshVertexLayout,), inputRate = .VERTEX}},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	VERTEX_ATTRIBUTES_PER_TYPE := map[VertexLayout][]vk.VertexInputAttributeDescription {
		.Mesh = {
			// {binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = 0},
			// {binding = 1, location = 1, format = .R32G32B32_SFLOAT, offset = 0},
			// {binding = 2, location = 2, format = .R32G32_SFLOAT, offset = 0},
			{ 
				binding = 0, 
				location = 0, 
				format = .R32G32B32_SFLOAT, 
				offset = u32(offset_of(MeshVertexLayout, position)),
			}, 
			{
				binding = 0,
				location = 1,
				format = .R32G32B32_SFLOAT,
				offset = u32(offset_of(MeshVertexLayout, color)),
			}, {
				binding = 0,
				location = 2,
				format = .R32G32_SFLOAT,
				offset = u32(offset_of(MeshVertexLayout, uv)),
			}},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INPUT_ASSEMBLY_PER_PRIMITIVE_TYPE := map[PrimitiveType]vk.PipelineInputAssemblyStateCreateInfo{
		.TriangleList = {
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology = .TRIANGLE_LIST,
		},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	RASTERIZER_STATE_PER_TYPE := map[RasterizerType]vk.PipelineRasterizationStateCreateInfo {
		.Fill = {
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			polygonMode = .FILL,
			lineWidth = 1.0,
		},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	MULTISAMPLER_STATE_PER_SAMPLE_TYPE := map[MultisamplingType]vk.PipelineMultisampleStateCreateInfo{
		._1 = {sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, rasterizationSamples = {._1}},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	DEPTH_STENCIL_STATE_PER_TYPE := map[DepthStencilType]vk.PipelineDepthStencilStateCreateInfo{
		.None = {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = false,
			depthWriteEnable = false,
			depthCompareOp = .NEVER,
			stencilTestEnable = false,
		},
		.DepthTestWrite = {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			minDepthBounds = 0,
			maxDepthBounds = 1,
			stencilTestEnable = false,
		},
		.DepthTestReadOnly = {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = true,
			depthWriteEnable = false,
			depthCompareOp = .LESS,
			minDepthBounds = 0,
			maxDepthBounds = 1,
			stencilTestEnable = false,
		},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	COLOR_BLEND_PER_TYPE := map[ColorBlendType]vk.PipelineColorBlendAttachmentState {
		.Default = {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = false,
			srcColorBlendFactor = .ONE,
			dstColorBlendFactor = .ZERO,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp = .ADD,
		},
	}

	//---------------------------------------------------------------------------//

	PIPELINE_CACHE_FILE := "app_data/bin/cache/pipeline/pipeline.cache"

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		vk_pipeline_cache: vk.PipelineCache,
	}

	//---------------------------------------------------------------------------//

	backend_init_pipelines :: proc() {
		pipeline_cache, ok := os.read_entire_file(
			PIPELINE_CACHE_FILE,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer free(raw_data(pipeline_cache), G_RENDERER_ALLOCATORS.temp_allocator)

		if ok == false {
			log.warn("Failed to read pipeline cache")
		}

		// Create pipeline cache
		create_info := vk.PipelineCacheCreateInfo {
			sType = .PIPELINE_CACHE_CREATE_INFO,
		}

		if ok && len(pipeline_cache) > 0 {
			create_info.pInitialData = raw_data(pipeline_cache)
			create_info.initialDataSize = len(pipeline_cache)
		}

		vk.CreatePipelineCache(
			G_RENDERER.device,
			&create_info,
			nil,
			&INTERNAL.vk_pipeline_cache,
		)
	}

	//---------------------------------------------------------------------------//

	backend_deinit_pipelines :: proc() {
		cache_size: int

		vk.GetPipelineCacheData(G_RENDERER.device, INTERNAL.vk_pipeline_cache, &cache_size, nil)

		cache_data := make([]u8, cache_size, G_RENDERER_ALLOCATORS.temp_allocator)

		vk.GetPipelineCacheData(
			G_RENDERER.device,
			INTERNAL.vk_pipeline_cache,
			&cache_size,
			raw_data(cache_data),
		)

		os.write_entire_file(PIPELINE_CACHE_FILE, cache_data)
	}

	//---------------------------------------------------------------------------//

	backend_create_graphics_pipeline :: proc(
		p_pipeline_desc: PipelineDesc,
		p_pipeline: ^PipelineResource,
	) -> bool {

		vert_shader := get_shader(p_pipeline_desc.vert_shader)
		frag_shader := get_shader(p_pipeline_desc.frag_shader)

		// create stage info for each shader
		vertex_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert_shader.vk_module,
			pName = "main",
		}
		fragment_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag_shader.vk_module,
			pName = "main",
		}

		shader_stages := []vk.PipelineShaderStageCreateInfo{
			vertex_stage_info,
			fragment_stage_info,
		}

		// Input assembly
		input_assembly_state := INPUT_ASSEMBLY_PER_PRIMITIVE_TYPE[p_pipeline_desc.primitive_type]

		// Vertex layout
		vertex_binding_descriptions := VERTEX_BINDINGS_PER_TYPE[p_pipeline_desc.vertex_layout]
		vertex_attribute_descriptions := VERTEX_ATTRIBUTES_PER_TYPE[p_pipeline_desc.vertex_layout]

		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount   = u32(len(vertex_binding_descriptions)),
			pVertexBindingDescriptions      = &vertex_binding_descriptions[0],
			vertexAttributeDescriptionCount = u32(len(vertex_attribute_descriptions)),
			pVertexAttributeDescriptions    = &vertex_attribute_descriptions[0],
		}

		// Rasterizer
		raster_state := RASTERIZER_STATE_PER_TYPE[p_pipeline_desc.resterizer_type]

		// Multisampler
		multisample_state := MULTISAMPLER_STATE_PER_SAMPLE_TYPE[p_pipeline_desc.multisampling_type]

		// Color attachments blending
		color_blend_attachments := make(
			[]vk.PipelineColorBlendAttachmentState,
			len(p_pipeline_desc.render_target_blend_types),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(color_blend_attachments, G_RENDERER_ALLOCATORS.temp_allocator)

		for blend_type, i in p_pipeline_desc.render_target_blend_types {
			color_blend_attachments[i] = COLOR_BLEND_PER_TYPE[blend_type]
		}

		color_blending_state := vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = u32(len(color_blend_attachments)),
			pAttachments = &color_blend_attachments[0],
			blendConstants = {0.0, 0.0, 0.0, 0.0},
		}

		// Depth stencil
		depth_stencil := DEPTH_STENCIL_STATE_PER_TYPE[p_pipeline_desc.depth_stencil_type]

		// Pipeline layout
		pipeline_layout_desc := PipelineLayoutDesc {
			name            = p_pipeline_desc.name,
			layout_type     = .GRAPHICS,
			vert_shader_ref = p_pipeline_desc.vert_shader,
			frag_shader_ref = p_pipeline_desc.frag_shader,
		}

		p_pipeline.pipeline_layout = create_graphics_pipeline_layout(pipeline_layout_desc)

		if p_pipeline.pipeline_layout == InvalidPipelineLayoutRef {
			log.warnf("Failed to create pipeline layout when creating the pipeline")
			return false
		}

		// Map color attachment formats
		color_attachment_formats := make(
			[]vk.Format,
			len(p_pipeline_desc.render_target_formats),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(color_attachment_formats, G_RENDERER_ALLOCATORS.temp_allocator)

		for format, i in p_pipeline_desc.render_target_formats {
			color_attachment_formats[i] = G_IMAGE_FORMAT_MAPPING[format]
		}

		// Map depth format
		depth_format := G_IMAGE_FORMAT_MAPPING[p_pipeline_desc.depth_format]

		// Dynamic rendering 
		pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
			sType                   = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount    = u32(len(color_attachment_formats)),
			pColorAttachmentFormats = &color_attachment_formats[0],
			depthAttachmentFormat   = depth_format,
		}

		dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR, .LINE_WIDTH}
		dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
			sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = u32(len(dynamic_states)),
			pDynamicStates    = raw_data(dynamic_states),
		}

		viewport_state := vk.PipelineViewportStateCreateInfo {
			sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			scissorCount  = 1,
			viewportCount = 1,
		}

		pipeline_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			pDynamicState       = &dynamic_state_create_info,
			pNext               = &pipeline_rendering_create_info,
			stageCount          = u32(len(shader_stages)),
			pStages             = raw_data(shader_stages),
			pVertexInputState   = &vertex_input_info,
			pInputAssemblyState = &input_assembly_state,
			pRasterizationState = &raster_state,
			pMultisampleState   = &multisample_state,
			pColorBlendState    = &color_blending_state,
			pDepthStencilState  = &depth_stencil,
			layout              = get_pipeline_layout(
				p_pipeline.pipeline_layout,
			).vk_pipeline_layout,
			pViewportState      = &viewport_state,
		}

		if res := vk.CreateGraphicsPipelines(
			   G_RENDERER.device,
			   0,
			   1,
			   &pipeline_info,
			   nil,
			   &p_pipeline.vk_pipeline,
		   ); res != .SUCCESS {
			log.warnf("Couldn't create graphics pipeline: %s", res)
			return false
		}

		return true
	}

	//---------------------------------------------------------------------------//


	@(private = "file")
	vk_pipeline_stages_mapping := []vk.PipelineStageFlag{
		.TOP_OF_PIPE,
		.DRAW_INDIRECT,
		.VERTEX_INPUT,
		.VERTEX_SHADER,
		.GEOMETRY_SHADER,
		.FRAGMENT_SHADER,
		.EARLY_FRAGMENT_TESTS,
		.LATE_FRAGMENT_TESTS,
		.COLOR_ATTACHMENT_OUTPUT,
		.COMPUTE_SHADER,
		.TRANSFER,
		.BOTTOM_OF_PIPE,
		.HOST,
		.ALL_GRAPHICS,
		.ALL_COMMANDS,
	}

	backend_map_pipeline_stage :: proc(
		p_stage: PipelineStageFlagBits,
	) -> vk.PipelineStageFlag {
		return vk_pipeline_stages_mapping[int(p_stage)]
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline :: proc(p_pipeline: ^PipelineResource) {
		vk.DestroyPipeline(G_RENDERER.device, p_pipeline.vk_pipeline, nil)
	}
	
	//---------------------------------------------------------------------------//
}
