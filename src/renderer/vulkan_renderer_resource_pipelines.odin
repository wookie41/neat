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
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	PipelineLayoutCacheEntry :: struct {
		vk_pipeline_layout: vk.PipelineLayout,
		ref_count:          u16,
	}

	//---------------------------------------------------------------------------//

	BackendGraphicsPipelineResource :: struct {
		vk_pipeline:        vk.Pipeline,
		vk_pipeline_layout: vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	BackendComputePipelineResource :: struct {
		vk_pipeline:        vk.Pipeline,
		vk_pipeline_layout: vk.PipelineLayout,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	VERTEX_BINDINGS_PER_TYPE := map[VertexLayout][]vk.VertexInputBindingDescription {
		.Empty = {},
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
		.Empty = {},
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
			.Default = {
				sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
				polygonMode = .FILL,
				lineWidth = 1.0,
				cullMode = {.BACK},
			},
			.Shadows = {
				sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
				polygonMode = .FILL,
				lineWidth = 1.0,
				cullMode = {.FRONT},
				depthClampEnable = true,
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
				depthCompareOp = .GREATER_OR_EQUAL,
				minDepthBounds = 0,
				maxDepthBounds = 1,
				stencilTestEnable = false,
			},
			.DepthTestReadOnly = {
				sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
				depthTestEnable = true,
				depthWriteEnable = false,
				depthCompareOp = .GREATER_OR_EQUAL,
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

	backend_pipelines_init :: proc() -> bool {
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
			MAX_GRAPHICS_PIPELINES + MAX_COMPUTE_PIPELINES,
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

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_pipelines_deinit :: proc() {
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

	backend_graphics_pipeline_create :: proc(p_ref: GraphicsPipelineRef) -> bool {

		pipeline_idx := get_graphics_pipeline_idx(p_ref)
		pipeline := &g_resources.graphics_pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_graphics_pipelines[pipeline_idx]

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
			pName = "VSMain",
		}
		fragment_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = backend_frag_shader.vk_module,
			pName = "PSMain",
		}

		shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_stage_info, fragment_stage_info}

		// Input assembly
		input_assembly_state := INPUT_ASSEMBLY_PER_PRIMITIVE_TYPE[render_pass.desc.primitive_type]

		// Vertex layout
		vertex_binding_descriptions := VERTEX_BINDINGS_PER_TYPE[pipeline.desc.vertex_layout]
		vertex_attribute_descriptions := VERTEX_ATTRIBUTES_PER_TYPE[pipeline.desc.vertex_layout]

		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		}
		if pipeline.desc.vertex_layout != .Empty {
			vertex_input_info.vertexBindingDescriptionCount = u32(len(vertex_binding_descriptions))
			vertex_input_info.pVertexBindingDescriptions = &vertex_binding_descriptions[0]
			vertex_input_info.vertexAttributeDescriptionCount = u32(
				len(vertex_attribute_descriptions),
			)
			vertex_input_info.pVertexAttributeDescriptions = &vertex_attribute_descriptions[0]
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

		// Depth stencil
		depth_stencil := DEPTH_STENCIL_STATE_PER_TYPE[render_pass.desc.depth_stencil_type]

		// Pipeline layout
		pipeline_layout_hash := hash_pipeline_layout(vert_shader.hash, frag_shader.hash)
		vk_pipeline_layout := get_cached_or_create_pipeline_layout(
			pipeline_layout_hash,
			pipeline.desc.bind_group_layout_refs,
			pipeline.desc.push_constants,
		) or_return
		backend_pipeline.vk_pipeline_layout = vk_pipeline_layout

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
			depthAttachmentFormat   = depth_format,
		}

		color_blending_state : vk.PipelineColorBlendStateCreateInfo 
		if len(render_pass.desc.layout.render_target_blend_types) > 0 {
			
			color_blending_state = {
				sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
				logicOpEnable = false,
				logicOp = .COPY,
				attachmentCount = u32(len(color_blend_attachments)),
				pAttachments = &color_blend_attachments[0],
				blendConstants = {0.0, 0.0, 0.0, 0.0},
			}	

			pipeline_rendering_create_info.colorAttachmentCount    = u32(len(color_attachment_formats))
			pipeline_rendering_create_info.pColorAttachmentFormats = &color_attachment_formats[0]
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
	backend_graphics_pipeline_destroy :: proc(p_pipeline_ref: GraphicsPipelineRef) {

		pipeline_idx := get_graphics_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_graphics_pipelines[pipeline_idx]

		pipeline_layout_hash := hash_pipeline_layout(p_pipeline_ref)
		assert(pipeline_layout_hash in INTERNAL.pipeline_layout_cache)

		cache_entry := &INTERNAL.pipeline_layout_cache[pipeline_layout_hash]
		assert(cache_entry.ref_count > 0)
		cache_entry.ref_count -= 1

		if cache_entry.ref_count == 0 {		
			delete_key(&INTERNAL.pipeline_layout_cache, pipeline_layout_hash)

			pipeline_layout_to_delete := defer_resource_delete(safe_destroy_pipeline_layout, vk.PipelineLayout)
			pipeline_layout_to_delete^ = cache_entry.vk_pipeline_layout	
		}

		pipeline_to_delete := defer_resource_delete(safe_destroy_pipeline, vk.Pipeline)
		pipeline_to_delete^ = backend_pipeline.vk_pipeline
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_graphics_pipeline_bind :: proc(
		p_pipeline_ref: GraphicsPipelineRef,
		p_cmd_buffer_ref: CommandBufferRef,
	) {
		pipeline_idx := get_graphics_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_graphics_pipelines[pipeline_idx]

		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buffer_ref)]
		vk.CmdBindPipeline(backend_cmd_buffer.vk_cmd_buff, .GRAPHICS, backend_pipeline.vk_pipeline)
	}

	hash_pipeline_layout :: proc {
		hash_graphics_pipeline_layout_ref,
		hash_compute_pipeline_layout_ref,
		hash_graphics_pipeline_layout_shaders,
		hash_compute_pipeline_layout_shaders,
	}
	//---------------------------------------------------------------------------//

	@(private = "file")
	hash_graphics_pipeline_layout_ref :: #force_inline proc(
		p_pipeline_ref: GraphicsPipelineRef,
	) -> u32 {
		pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(p_pipeline_ref)]
		vert_shader_hash := g_resources.shaders[get_shader_idx(pipeline.desc.vert_shader_ref)].hash
		frag_shader_hash := g_resources.shaders[get_shader_idx(pipeline.desc.frag_shader_ref)].hash
		return hash_graphics_pipeline_layout_shaders(vert_shader_hash,frag_shader_hash)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	hash_compute_pipeline_layout_ref :: #force_inline proc(
		p_pipeline_ref: ComputePipelineRef,
	) -> u32 {
		pipeline := &g_resources.compute_pipelines[get_compute_pipeline_idx(p_pipeline_ref)]
		return hash_compute_pipeline_layout_shaders(g_resources.shaders[get_shader_idx(pipeline.desc.compute_shader_ref)].hash)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	hash_graphics_pipeline_layout_shaders :: proc(
		p_vert_shader_hash: u32,
		p_frag_shader_hash: u32,
	) -> u32 {
		return(
			p_vert_shader_hash ~
			p_frag_shader_hash ~
			u32(ShaderStage.Vertex) ~
			u32(ShaderStage.Pixel) \
		)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	hash_compute_pipeline_layout_shaders :: proc(
		p_compute_hash: u32,
	) -> u32 {
		return (p_compute_hash ~ u32(ShaderStage.Compute))
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_pipeline_layout :: proc(
		p_pipeline_layout_hash: u32,
		p_bind_group_layout_refs: []BindGroupLayoutRef,
		p_push_constants: []PushConstantDesc,
	) -> (
		vk.PipelineLayout,
		bool,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		// Gather descriptor layouts from each bind group layout
		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			len(p_bind_group_layout_refs),
			temp_arena.allocator,
		)

		for bind_group_layout_ref, i in p_bind_group_layout_refs {

			if bind_group_layout_ref == InvalidBindGroupLayoutRef {
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
			len(p_push_constants),
			temp_arena.allocator,
		)

		for push_constant, i in p_push_constants {
			push_constant_ranges[i] = vk.PushConstantRange {
				offset = push_constant.offset_in_bytes,
				size   = push_constant.size_in_bytes,
			}

			if .Vertex in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.VERTEX}
			}

			if .Pixel in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.FRAGMENT}
			}

			if .Compute in push_constant.shader_stages {
				push_constant_ranges[i].stageFlags += {.COMPUTE}
			}
		}

		if len(p_push_constants) > 0 {
			create_info.pushConstantRangeCount = u32(len(p_push_constants))
			create_info.pPushConstantRanges = &push_constant_ranges[0]
		}

		vk_pipeline_layout: vk.PipelineLayout
		if vk.CreatePipelineLayout(G_RENDERER.device, &create_info, nil, &vk_pipeline_layout) !=
		   .SUCCESS {
			log.warn("Failed to create pipeline layout")
			return vk.PipelineLayout{}, false
		}

		// Add entry to cache
		INTERNAL.pipeline_layout_cache[p_pipeline_layout_hash] = PipelineLayoutCacheEntry {
			ref_count          = 1,
			vk_pipeline_layout = vk_pipeline_layout,
		}

		return vk_pipeline_layout, true
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	DescriptorLayoutBindingHashEntry :: struct {
		type:  u32,
		slot:  u32,
		count: u32,
	}

	//---------------------------------------------------------------------------//

	backend_compute_pipeline_create :: proc(p_ref: ComputePipelineRef) -> bool {

		pipeline_idx := get_compute_pipeline_idx(p_ref)
		pipeline := &g_resources.compute_pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_compute_pipelines[pipeline_idx]

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		compute_shader_idx := get_shader_idx(pipeline.desc.compute_shader_ref)
		compute_shader := &g_resources.shaders[compute_shader_idx]
		backend_compute_shader := &g_resources.backend_shaders[compute_shader_idx]

		compute_stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.COMPUTE},
			module = backend_compute_shader.vk_module,
			pName = "CSMain",
		}

		// Pipeline layout 
		backend_pipeline.vk_pipeline_layout = get_cached_or_create_pipeline_layout(
			hash_pipeline_layout(compute_shader.hash),
			pipeline.desc.bind_group_layout_refs,
			pipeline.desc.push_constants,
		) or_return

		pipeline_info := vk.ComputePipelineCreateInfo {
			sType  = .COMPUTE_PIPELINE_CREATE_INFO,
			layout = backend_pipeline.vk_pipeline_layout,
			stage  = compute_stage_info,
		}

		if res := vk.CreateComputePipelines(
			G_RENDERER.device,
			0,
			1,
			&pipeline_info,
			nil,
			&backend_pipeline.vk_pipeline,
		); res != .SUCCESS {
			log.warnf("Couldn't create compute pipeline: %s", res)
			return false
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_compute_pipeline_destroy :: proc(p_pipeline_ref: ComputePipelineRef) {

		pipeline_idx := get_compute_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_compute_pipelines[pipeline_idx]

		pipeline_layout_hash := hash_pipeline_layout(p_pipeline_ref)
		assert(pipeline_layout_hash in INTERNAL.pipeline_layout_cache)

		cache_entry := &INTERNAL.pipeline_layout_cache[pipeline_layout_hash]
		assert(cache_entry.ref_count > 0)
		cache_entry.ref_count -= 1

		// Delete the pipeline layout if needed
		if cache_entry.ref_count == 0 {
			delete_key(&INTERNAL.pipeline_layout_cache, pipeline_layout_hash)

			pipeline_layout_to_delete := defer_resource_delete(safe_destroy_pipeline_layout, vk.PipelineLayout)
			pipeline_layout_to_delete^ = cache_entry.vk_pipeline_layout	
		}

		pipeline_to_delete := defer_resource_delete(safe_destroy_pipeline, vk.Pipeline)
		pipeline_to_delete^ = backend_pipeline.vk_pipeline
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	get_cached_or_create_pipeline_layout :: proc(
		p_pipeline_layout_hash: u32,
		p_bind_group_layout_refs: []BindGroupLayoutRef,
		p_push_constants: []PushConstantDesc,
	) -> (
		vk.PipelineLayout,
		bool,
	) {
		// First check if we have a matching pipeline layout in the cache
		if p_pipeline_layout_hash in INTERNAL.pipeline_layout_cache {
			// If so, use it
			cache_entry := &INTERNAL.pipeline_layout_cache[p_pipeline_layout_hash]
			cache_entry.ref_count += 1
			return cache_entry.vk_pipeline_layout, true
		}

		// Otherwise create a new one 
		pipeline_layout, success := create_pipeline_layout(
			p_pipeline_layout_hash,
			p_bind_group_layout_refs,
			p_push_constants,
		)
		if success == false {
			return vk.PipelineLayout{}, false
		}

		return pipeline_layout, true
	}
	//---------------------------------------------------------------------------//


	@(private)
	backend_compute_pipeline_bind :: proc(
		p_pipeline_ref: ComputePipelineRef,
		p_cmd_buffer_ref: CommandBufferRef,
	) {
		pipeline_idx := get_compute_pipeline_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_compute_pipelines[pipeline_idx]

		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buffer_ref)]
		vk.CmdBindPipeline(backend_cmd_buffer.vk_cmd_buff, .COMPUTE, backend_pipeline.vk_pipeline)
	}

	//---------------------------------------------------------------------------//

	@(private="file")
	safe_destroy_pipeline_layout :: proc(p_user_data: rawptr) {
		vk_pipeline_layout := (^vk.PipelineLayout)(p_user_data)^
		vk.DestroyPipelineLayout(G_RENDERER.device, vk_pipeline_layout, nil)
	}

	//---------------------------------------------------------------------------//

	@(private="file")
	safe_destroy_pipeline :: proc(p_user_data: rawptr) {
		vk_pipeline := (^vk.Pipeline)(p_user_data)^
		vk.DestroyPipeline(G_RENDERER.device, vk_pipeline, nil)
	}

	//---------------------------------------------------------------------------//
}
