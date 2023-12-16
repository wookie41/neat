package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	DeferredPipelineDelete :: struct {
		pipeline_layout_hash: u32,
		vk_pipeline:          vk.Pipeline,
		wait_fence:           vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		pipeline_layout_cache:          map[u32]PipelineLayoutCacheEntry,
		vk_pipeline_cache:              vk.PipelineCache,
		vk_empty_descriptor_set_layout: vk.DescriptorSetLayout,
		deferred_pipeline_deletions:    [dynamic]DeferredPipelineDelete,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	PipelineLayoutCacheEntry :: struct {
		vk_pipeline_layout: vk.PipelineLayout,
		ref_count:          u16,
	}

	//---------------------------------------------------------------------------//

	BackendPipelineResource :: struct {
		vk_pipeline:        vk.Pipeline,
		vk_pipeline_layout: vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	VERTEX_BINDINGS_PER_TYPE := map[VertexLayout][]vk.VertexInputBindingDescription {
		// position, uv, normal, tangent
		.Mesh = {
			{binding = 0, stride = size_of(glsl.vec3), inputRate = .VERTEX},
			{binding = 1, stride = size_of(glsl.vec2), inputRate = .VERTEX},
			{binding = 2, stride = size_of(glsl.vec3), inputRate = .VERTEX},
			{binding = 3, stride = size_of(glsl.vec3), inputRate = .VERTEX},
		},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	VERTEX_ATTRIBUTES_PER_TYPE := map[VertexLayout][]vk.VertexInputAttributeDescription {
		// position, uv, normal, tangent
		.Mesh = {
			{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = 0},
			{binding = 1, location = 1, format = .R32G32_SFLOAT, offset = 0},
			{binding = 2, location = 2, format = .R32G32B32_SFLOAT, offset = 0},
			{binding = 3, location = 3, format = .R32G32B32_SFLOAT, offset = 0},
		},
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INPUT_ASSEMBLY_PER_PRIMITIVE_TYPE :=
		map[PrimitiveType]vk.PipelineInputAssemblyStateCreateInfo {
			.TriangleList = {
				sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
				topology = .TRIANGLE_LIST,
				primitiveRestartEnable = false,
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
	MULTISAMPLER_STATE_PER_SAMPLE_TYPE :=
		map[MultisamplingType]vk.PipelineMultisampleStateCreateInfo {
			._1 = {sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, rasterizationSamples = {._1}},
		}

	//---------------------------------------------------------------------------//

	@(private = "file")
	DEPTH_STENCIL_STATE_PER_TYPE := map[DepthStencilType]vk.PipelineDepthStencilStateCreateInfo {
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

	backend_init_pipelines :: proc() -> bool {
		// Create an empty descriptor set layout used to fill gaps
		{
			create_info := vk.DescriptorSetLayoutCreateInfo {
					sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = 0,
				}

			if vk.CreateDescriptorSetLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &INTERNAL.vk_empty_descriptor_set_layout,
			   ) !=
			   .SUCCESS {
				return false
			}
		}

		// Init pipeline layout cache
		INTERNAL.pipeline_layout_cache = make(
			map[u32]PipelineLayoutCacheEntry,
			MAX_PIPELINES,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		// Try to read pipeline cache file
		pipeline_cache, ok := os.read_entire_file(
			PIPELINE_CACHE_FILE,
			G_RENDERER_ALLOCATORS.main_allocator,
		)
		defer free(raw_data(pipeline_cache))

		// Create pipeline cache
		create_info := vk.PipelineCacheCreateInfo {
			sType = .PIPELINE_CACHE_CREATE_INFO,
		}

		if ok && len(pipeline_cache) > 0 {
			create_info.pInitialData = raw_data(pipeline_cache)
			create_info.initialDataSize = len(pipeline_cache)
		} else {
			log.warn("Failed to read pipeline cache")
		}

		vk.CreatePipelineCache(G_RENDERER.device, &create_info, nil, &INTERNAL.vk_pipeline_cache)

		INTERNAL.deferred_pipeline_deletions = make([dynamic]DeferredPipelineDelete)

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_pipelines_update :: proc() {

		// Process deferred deletes
		deferred_deletes := make([dynamic]DeferredPipelineDelete)
		for deferred_delete in &INTERNAL.deferred_pipeline_deletions {

			// Command buffer with using this pipeline is still in use
			if vk.GetFenceStatus(G_RENDERER.device, deferred_delete.wait_fence) == .NOT_READY {
				append(&deferred_deletes, deferred_delete)
				continue

			}

			// Safe to delete pipeline

			cache_entry := &INTERNAL.pipeline_layout_cache[deferred_delete.pipeline_layout_hash]
			assert(cache_entry.ref_count > 0)
			cache_entry.ref_count -= 1

			if cache_entry.ref_count == 0 {
				vk.DestroyPipelineLayout(G_RENDERER.device, cache_entry.vk_pipeline_layout, nil)
				delete_key(&INTERNAL.pipeline_layout_cache, deferred_delete.pipeline_layout_hash)
			}

			vk.DestroyPipeline(G_RENDERER.device, deferred_delete.vk_pipeline, nil)

		}

		clear(&INTERNAL.deferred_pipeline_deletions)
		INTERNAL.deferred_pipeline_deletions = deferred_deletes
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_deinit_pipelines :: proc() {
		cache_size: int

		vk.GetPipelineCacheData(G_RENDERER.device, INTERNAL.vk_pipeline_cache, &cache_size, nil)

		cache_data := make([]u8, cache_size, G_RENDERER_ALLOCATORS.main_allocator)
		defer delete(cache_data, G_RENDERER_ALLOCATORS.main_allocator)
		defer delete(INTERNAL.pipeline_layout_cache)

		vk.GetPipelineCacheData(
			G_RENDERER.device,
			INTERNAL.vk_pipeline_cache,
			&cache_size,
			raw_data(cache_data),
		)

		os.write_entire_file(PIPELINE_CACHE_FILE, cache_data)
	}

	//---------------------------------------------------------------------------//

	backend_create_graphics_pipeline :: proc(p_ref: PipelineRef) -> bool {

		pipeline_idx := get_pipeline_idx(p_ref)
		pipeline := &g_resources.pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_pipelines[pipeline_idx]

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		vertex_shader_idx := get_shader_idx(pipeline.desc.vert_shader_ref)
		fragment_shader_idx := get_shader_idx(pipeline.desc.frag_shader_ref)

		vert_shader := &g_resources.shaders[vertex_shader_idx]
		frag_shader := &g_resources.shaders[fragment_shader_idx]

		backend_vert_shader := &g_resources.backend_shaders[vertex_shader_idx]
		backend_frag_shader := &g_resources.backend_shaders[fragment_shader_idx]

		render_pass := &g_resources.render_passes[get_render_pass_idx(pipeline.desc.render_pass_ref)]

		// create stage info for each shader
		vertex_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = backend_vert_shader.vk_module,
			pName = "main",
		}
		fragment_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = backend_frag_shader.vk_module,
			pName = "main",
		}

		shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_stage_info, fragment_stage_info}

		// Input assembly
		input_assembly_state := INPUT_ASSEMBLY_PER_PRIMITIVE_TYPE[render_pass.desc.primitive_type]

		// Vertex layout
		vertex_binding_descriptions := VERTEX_BINDINGS_PER_TYPE[pipeline.desc.vertex_layout]
		vertex_attribute_descriptions := VERTEX_ATTRIBUTES_PER_TYPE[pipeline.desc.vertex_layout]

		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount   = u32(len(vertex_binding_descriptions)),
			pVertexBindingDescriptions      = &vertex_binding_descriptions[0],
			vertexAttributeDescriptionCount = u32(len(vertex_attribute_descriptions)),
			pVertexAttributeDescriptions    = &vertex_attribute_descriptions[0],
		}

		// Rasterizer
		raster_state := RASTERIZER_STATE_PER_TYPE[render_pass.desc.resterizer_type]

		// Multisampler
		multisample_state :=
			MULTISAMPLER_STATE_PER_SAMPLE_TYPE[render_pass.desc.multisampling_type]

		// Color attachments blending
		color_blend_attachments := make(
			[]vk.PipelineColorBlendAttachmentState,
			len(render_pass.desc.layout.render_target_blend_types),
			temp_arena.allocator,
		)

		for blend_type, i in render_pass.desc.layout.render_target_blend_types {
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
		depth_stencil := DEPTH_STENCIL_STATE_PER_TYPE[render_pass.desc.depth_stencil_type]

		// Pipeline layout - first check if we have a matching pipeline layout in the cache
		pipeline_layout_hash := vert_shader.hash ~ frag_shader.hash
		if pipeline_layout_hash in INTERNAL.pipeline_layout_cache {
			// If so, use it
			cache_entry := &INTERNAL.pipeline_layout_cache[pipeline_layout_hash]
			cache_entry.ref_count += 1
			backend_pipeline.vk_pipeline_layout = cache_entry.vk_pipeline_layout
		} else {
			// Otherwise create a new one 
			success := create_pipeline_layout(pipeline_idx, pipeline_layout_hash)
			if success == false {
				return false
			}
		}

		// Map color attachment formats
		color_attachment_formats := make(
			[]vk.Format,
			len(render_pass.desc.layout.render_target_formats),
			temp_arena.allocator,
		)
		defer delete(color_attachment_formats, temp_arena.allocator)


		for format, i in render_pass.desc.layout.render_target_formats {
			color_attachment_formats[i] = G_IMAGE_FORMAT_MAPPING[format]
		}

		// Map depth format
		depth_format := G_IMAGE_FORMAT_MAPPING[render_pass.desc.layout.depth_format]

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
			layout              = backend_pipeline.vk_pipeline_layout,
			pViewportState      = &viewport_state,
		}

		if res := vk.CreateGraphicsPipelines(
			G_RENDERER.device,
			0,
			1,
			&pipeline_info,
			nil,
			&backend_pipeline.vk_pipeline,
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

	backend_map_pipeline_stage :: proc(p_stage: PipelineStageFlagBits) -> vk.PipelineStageFlag {
		return vk_pipeline_stages_mapping[int(p_stage)]
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline :: proc(p_pipeline_ref: PipelineRef) {

		pipeline_idx := get_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_pipelines[pipeline_idx]

		pipeline_layout_hash := hash_pipeline_layout(pipeline_idx)
		assert(pipeline_layout_hash in INTERNAL.pipeline_layout_cache)

		cache_entry := &INTERNAL.pipeline_layout_cache[pipeline_layout_hash]
		assert(cache_entry.ref_count > 0)
		cache_entry.ref_count -= 1

		// Delete the pipeline layout if needed
		if cache_entry.ref_count == 0 {
			vk.DestroyPipelineLayout(G_RENDERER.device, cache_entry.vk_pipeline_layout, nil)
			delete_key(&INTERNAL.pipeline_layout_cache, pipeline_layout_hash)
		}

		vk.DestroyPipeline(G_RENDERER.device, backend_pipeline.vk_pipeline, nil)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_reset_pipeline :: proc(p_pipeline_ref: PipelineRef) {

		pipeline_idx := get_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_pipelines[pipeline_idx]

		append(
			&INTERNAL.deferred_pipeline_deletions,
			DeferredPipelineDelete{
				pipeline_layout_hash = hash_pipeline_layout(pipeline_idx),
				vk_pipeline = backend_pipeline.vk_pipeline,
				wait_fence = G_RENDERER.frame_fences[get_frame_idx()],
			},
		)
	}

	//---------------------------------------------------------------------------//


	@(private)
	backend_bind_pipeline :: proc(
		p_pipeline_ref: PipelineRef,
		p_cmd_buffer_ref: CommandBufferRef,
	) {
		pipeline_idx := get_pipeline_idx(p_pipeline_ref)
		pipeline := &g_resources.pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_pipelines[pipeline_idx]

		bind_point := map_pipeline_bind_point(pipeline.type)
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buffer_ref)]
		vk.CmdBindPipeline(
			backend_cmd_buffer.vk_cmd_buff,
			bind_point,
			backend_pipeline.vk_pipeline,
		)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	hash_pipeline_layout :: #force_inline proc(p_pipeline_idx: u32) -> u32 {
		pipeline := &g_resources.pipelines[p_pipeline_idx]
		vert_shader_hash := g_resources.shaders[get_shader_idx(pipeline.desc.vert_shader_ref)].hash
		frag_shader_hash := g_resources.shaders[get_shader_idx(pipeline.desc.frag_shader_ref)].hash
		return vert_shader_hash ~ frag_shader_hash
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_pipeline_layout :: proc(p_pipeline_idx: u32, p_pipeline_layout_hash: u32) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		pipeline := &g_resources.pipelines[p_pipeline_idx]
		backend_pipeline := &g_resources.backend_pipelines[p_pipeline_idx]

		// Gather descriptor layouts from each bind group layout
		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			len(pipeline.desc.bind_group_layout_refs),
			temp_arena.allocator,
		)

		for bind_group_layout_ref, i in pipeline.desc.bind_group_layout_refs {

			if bind_group_layout_ref == InvalidBindGroupRefLayout {
				descriptor_set_layouts[i] = INTERNAL.vk_empty_descriptor_set_layout
				continue
			}

			bind_group_layout_idx := get_bind_group_layout_idx(bind_group_layout_ref)
			descriptor_set_layouts[i] =
				g_resources.backend_bind_group_layouts[bind_group_layout_idx].vk_descriptor_set_layout
		}

		// Create pipeline layout
		create_info := vk.PipelineLayoutCreateInfo {
			sType          = .PIPELINE_LAYOUT_CREATE_INFO,
			pSetLayouts    = raw_data(descriptor_set_layouts),
			setLayoutCount = u32(len(descriptor_set_layouts)),
		}

		push_constant_ranges := make(
			[]vk.PushConstantRange,
			len(pipeline.desc.push_constants),
			temp_arena.allocator,
		)

		for push_constant, i in pipeline.desc.push_constants {
			push_constant_ranges[i] = vk.PushConstantRange {
				offset = push_constant.offset_in_bytes,
				size   = push_constant.size_in_bytes,
			}

			if .Vertex in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.VERTEX}
			}

			if .Fragment in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.FRAGMENT}
			}

			if .Compute in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.COMPUTE}
			}
		}

		if len(pipeline.desc.push_constants) > 0 {
			create_info.pushConstantRangeCount = u32(len(pipeline.desc.push_constants))
			create_info.pPushConstantRanges = &push_constant_ranges[0]
		}

		if vk.CreatePipelineLayout(
			   G_RENDERER.device,
			   &create_info,
			   nil,
			   &backend_pipeline.vk_pipeline_layout,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create pipeline layout")
			return false
		}

		// Add entry to cache
		INTERNAL.pipeline_layout_cache[p_pipeline_layout_hash] = PipelineLayoutCacheEntry {
			ref_count          = 1,
			vk_pipeline_layout = backend_pipeline.vk_pipeline_layout,
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	DescriptorLayoutBindingHashEntry :: struct {
		type:  u32,
		slot:  u32,
		count: u32,
	}

	//---------------------------------------------------------------------------//
}
