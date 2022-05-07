package renderer

import "core:fmt"
import "core:math/linalg/glsl"
import "core:mem"
import "core:log"
import "core:time"
import "core:c"

import vk "vendor:vulkan"
import stb_image "vendor:stb/image"

import vma "../third_party/vma"

G_VT: struct {
	descriptor_set_layout:     vk.DescriptorSetLayout,
	pipeline_layout:           vk.PipelineLayout,
	pso:                       vk.Pipeline,
	vertex_shader_module:      vk.ShaderModule,
	fragment_shader_module:    vk.ShaderModule,
	command_pools:             [dynamic]vk.CommandPool,
	command_buffers:           [dynamic]vk.CommandBuffer,
	uniform_buffers:           [dynamic]vk.Buffer,
	uniform_buffer_allocation: [dynamic]vma.Allocation,
	vertex_buffer:             vk.Buffer,
	vertex_buffer_allocation:  vma.Allocation,
	index_buffer:              vk.Buffer,
	index_buffer_allocation:   vma.Allocation,
	start_time:                time.Time,
	descriptor_pool:           vk.DescriptorPool,
	descriptor_sets:           [dynamic]vk.DescriptorSet,
	texture_image:             vk.Image,
	texture_image_allocation:  vma.Allocation,
	texture_image_view:        vk.ImageView,
	texture_sampler:           vk.Sampler,
	depth_image:               vk.Image,
	depth_image_view:          vk.ImageView,
	depth_image_allocation:    vma.Allocation,
}

Vertex :: struct {
	position: glsl.vec3,
	color:    glsl.vec3,
	uv:       glsl.vec2,
}

vertex_binding_description := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

vertex_attributes_descriptions := []vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, position)),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = u32(offset_of(Vertex, uv)),
	},
}

g_vertices :: []Vertex{
	{{-0.5, -0.5, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
	{{0.5, -0.5, 0.0}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
	{{0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
	{{-0.5, 0.5, 0.0}, {1.0, 1.0, 1.0}, {0.0, 1.0}},
	{{-0.5, -0.5, -0.5}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
	{{0.5, -0.5, -0.5}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
	{{0.5, 0.5, -0.5}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
	{{-0.5, 0.5, -0.5}, {1.0, 1.0, 1.0}, {0.0, 1.0}},
}

g_indices :: []u16{0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4}

UniformBufferObject :: struct {
	model: glsl.mat4x4,
	view:  glsl.mat4x4,
	proj:  glsl.mat4x4,
}

init_vt :: proc() -> bool {

	{
		using G_RENDERER
		using G_VT

		start_time = time.now()

		vt_create_descriptor_set_layout()
		vt_create_uniform_buffers()
		vt_create_descriptor_pool()
		vk_create_descriptor_sets()

		// load the code
		vertex_shader_code := #load(
			"../../app_data/renderer/assets/shaders/setup_sdl2_debug.vert.spv",
		)
		fragment_shader_code := #load(
			"../../app_data/renderer/assets/shaders/setup_sdl2_debug.frag.spv",
		)

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
			sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount   = 1,
			pVertexBindingDescriptions      = &vertex_binding_description,
			vertexAttributeDescriptionCount = u32(len(vertex_attributes_descriptions)),
			pVertexAttributeDescriptions    = &vertex_attributes_descriptions[0],
		}

		// state for assembly
		input_assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
			sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology               = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
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

		depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
			sType             = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable   = true,
			depthWriteEnable  = true,
			depthCompareOp    = .LESS,
			minDepthBounds    = 0,
			maxDepthBounds    = 1,
			stencilTestEnable = false,
		}

		// pipeline layout
		pipeline_layout_info := vk.PipelineLayoutCreateInfo {
			sType          = .PIPELINE_LAYOUT_CREATE_INFO,
			pSetLayouts    = &descriptor_set_layout,
			setLayoutCount = 1,
		}

		if vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, &pipeline_layout) != .SUCCESS {
			fmt.eprintln("couldn't create pipeline layout")
			return false
		}

		pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
			sType                   = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount    = 1,
			pColorAttachmentFormats = &swapchain_format.format,
			depthAttachmentFormat   = .D32_SFLOAT,
		}

		dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
		dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
			sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = u32(len(dynamic_states)),
			pDynamicStates    = raw_data(dynamic_states),
		}

		viewport_state := vk.PipelineViewportStateCreateInfo {
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			scissorCount = 1,
			viewportCount = 1,
		}

		pipeline_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			pDynamicState       = &dynamic_state_create_info,
			pNext               = &pipeline_rendering_create_info,
			stageCount          = u32(len(shader_stages)),
			pStages             = raw_data(shader_stages),
			pVertexInputState   = &vertex_input_info,
			pInputAssemblyState = &input_assembly_info,
			pRasterizationState = &rasteriser,
			pMultisampleState   = &multisampling,
			pColorBlendState    = &colour_blending,
			pDepthStencilState  = &depth_stencil,
			layout              = pipeline_layout,
			pViewportState      = &viewport_state,
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
			sType = .COMMAND_POOL_CREATE_INFO,
			queueFamilyIndex = u32(queue_family_graphics_index),
			flags = {.RESET_COMMAND_BUFFER},
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

	vt_create_vertex_buffer()
	vt_create_index_buffer()
	vt_create_texture_image()
	vt_create_texture_image_view()
	vt_create_texture_sampler()
	vt_write_descriptor_sets()
	vt_create_depth_resources()

	return true
}

deinit_vt :: proc() {
	using G_VT
	using G_RENDERER

	vk.DestroySampler(device, texture_sampler, nil)
	vk.DestroyImageView(device, texture_image_view, nil)
	vma.destroy_image(vma_allocator, texture_image, texture_image_allocation)
	vk.DestroyDescriptorPool(device, descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(device, descriptor_set_layout, nil)

	vma.destroy_buffer(vma_allocator, vertex_buffer, vertex_buffer_allocation)
	vma.destroy_buffer(vma_allocator, index_buffer, index_buffer_allocation)

	for cmd_pool in command_pools {
		vk.DestroyCommandPool(device, cmd_pool, nil)
	}
	for buff, i in uniform_buffers {
		vma.destroy_buffer(vma_allocator, buff, uniform_buffer_allocation[i])
	}
	vk.DestroyShaderModule(device, vertex_shader_module, nil)
	vk.DestroyShaderModule(device, fragment_shader_module, nil)
	vk.DestroyPipeline(device, pso, nil)
	vk.DestroyPipelineLayout(device, pipeline_layout, nil)
}


vt_update :: proc(p_image_index: u32) -> vk.CommandBuffer {
	using G_VT
	using G_RENDERER

	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		pNext = nil,
		clearValue = {color = {float32 = {0, 0, 0, 1}}},
		imageLayout = .ATTACHMENT_OPTIMAL,
		imageView = swapchain_image_views[p_image_index],
		loadOp = .CLEAR,
		storeOp = .STORE,
	}

	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		pNext = nil,
		clearValue = {depthStencil = {depth = 1, stencil = 0}},
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		imageView = depth_image_view,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		colorAttachmentCount = 1,
		pDepthAttachment = &depth_attachment,
		layerCount = 1,
		viewMask = 0,
		pColorAttachments = &color_attachment,
		renderArea = {extent = G_RENDERER.swap_extent},
	}

	cmd_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		pNext = nil,
		flags = {.ONE_TIME_SUBMIT},
	}

	to_color_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .ATTACHMENT_OPTIMAL,
		image = swapchain_images[p_image_index],
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	to_present_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .ATTACHMENT_OPTIMAL,
		newLayout = .PRESENT_SRC_KHR,
		image = swapchain_images[p_image_index],
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
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

	cmd := command_buffers[frame_idx]
	vk.BeginCommandBuffer(cmd, &cmd_buffer_begin_info)

	vt_update_uniform_buffer()

	vk.CmdPipelineBarrier(
		cmd,
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_color_barrier,
	)
	vk.CmdBeginRendering(cmd, &rendering_info)
	vk.CmdBindPipeline(cmd, .GRAPHICS, pso)
	vk.CmdSetViewport(cmd, 0, 1, &viewport)
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		pipeline_layout,
		0,
		1,
		&descriptor_sets[frame_idx],
		0,
		nil,
	)

	offset := vk.DeviceSize{}

	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer, &offset)
	vk.CmdBindIndexBuffer(cmd, index_buffer, offset, .UINT16)
	vk.CmdDrawIndexed(cmd, u32(len(g_indices)), 1, 0, 0, 0)
	vk.CmdEndRendering(cmd)

	vk.CmdPipelineBarrier(
		cmd,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_present_barrier,
	)

	vk.EndCommandBuffer(cmd)

	return cmd
}

vt_create_vertex_buffer :: proc() {
	using G_RENDERER
	using G_VT

	buff_size := vk.DeviceSize(len(g_vertices) * size_of(Vertex))
	vertex_buffer, vertex_buffer_allocation = vt_create_buffer(
		buff_size,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		.AUTO,
		nil,
	)
	staging_buffer, staging_buffer_allocaction := vt_create_buffer(
		buff_size,
		{.TRANSFER_SRC},
		.AUTO_PREFER_HOST,
		{.HOST_ACCESS_SEQUENTIAL_WRITE},
	)

	vertex_data: rawptr
	vma.map_memory(vma_allocator, staging_buffer_allocaction, &vertex_data)
	mem.copy(vertex_data, raw_data(g_vertices), len(g_vertices) * size_of(Vertex))
	vma.unmap_memory(vma_allocator, staging_buffer_allocaction)

	vt_copy_buffer(staging_buffer, vertex_buffer, buff_size)

	vma.destroy_buffer(vma_allocator, staging_buffer, staging_buffer_allocaction)
}

vt_create_index_buffer :: proc() {
	using G_RENDERER
	using G_VT

	buff_size := vk.DeviceSize(len(g_indices) * size_of(g_indices[0]))
	index_buffer, index_buffer_allocation = vt_create_buffer(
		buff_size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.AUTO,
		nil,
	)
	staging_buffer, staging_buffer_allocaction := vt_create_buffer(
		buff_size,
		{.TRANSFER_SRC},
		.AUTO_PREFER_HOST,
		{.HOST_ACCESS_SEQUENTIAL_WRITE},
	)

	index_data: rawptr
	vma.map_memory(vma_allocator, staging_buffer_allocaction, &index_data)
	mem.copy(index_data, raw_data(g_indices), len(g_indices) * size_of(g_indices[0]))
	vma.unmap_memory(vma_allocator, staging_buffer_allocaction)

	vt_copy_buffer(staging_buffer, index_buffer, buff_size)

	vma.destroy_buffer(vma_allocator, staging_buffer, staging_buffer_allocaction)
}

vt_create_buffer :: proc(
	p_size: vk.DeviceSize,
	p_usage: vk.BufferUsageFlags,
	p_alloc_usage: vma.MemoryUsage,
	p_alloc_flags: vma.AllocationCreateFlags,
) -> (
	vk.Buffer,
	vma.Allocation,
) {
	using G_RENDERER
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = p_size,
		usage       = p_usage,
		sharingMode = .EXCLUSIVE,
	}
	alloc_info := vma.AllocationCreateInfo {
		usage = p_alloc_usage,
		flags = p_alloc_flags,
	}

	buffer: vk.Buffer
	alloc: vma.Allocation
	if vma.create_buffer(vma_allocator, &buffer_info, &alloc_info, &buffer, &alloc, nil) != .SUCCESS {
		log.warn("Failed to create buffer")
		return 0, nil
	}
	return buffer, alloc
}

vt_copy_buffer :: proc(
	p_src_buffer: vk.Buffer,
	p_dst_buffer: vk.Buffer,
	p_size: vk.DeviceSize,
) {
	using G_VT
	using G_RENDERER
	copy_cmd_buff := vt_begin_single_time_command_buffer()
	copy_region := vk.BufferCopy {
		size = p_size,
	}
	vk.CmdCopyBuffer(copy_cmd_buff, p_src_buffer, p_dst_buffer, 1, &copy_region)
	vt_end_single_time_command_buffer(copy_cmd_buff)
}

vt_create_descriptor_set_layout :: proc() {
	using G_RENDERER
	using G_VT

	ubo_layout_binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX},
	}

	sampler_layout_binding := vk.DescriptorSetLayoutBinding {
		binding = 1,
		descriptorType = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags = {.FRAGMENT},
	}

	layout_bindings := []vk.DescriptorSetLayoutBinding{
		ubo_layout_binding,
		sampler_layout_binding,
	}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(layout_bindings)),
		pBindings    = raw_data(layout_bindings),
	}

	if vk.CreateDescriptorSetLayout(device, &layout_info, nil, &descriptor_set_layout) != .SUCCESS {
		log.warn("Failed to create descriptor set layout")
	}
}

vt_create_uniform_buffers :: proc() {
	using G_RENDERER
	using G_VT

	buff_size := vk.DeviceSize(size_of(UniformBufferObject))

	resize(&uniform_buffers, int(num_frames_in_flight))
	resize(&uniform_buffer_allocation, int(num_frames_in_flight))

	for i in 0 ..< num_frames_in_flight {
		uniform_buffers[i], uniform_buffer_allocation[i] = vt_create_buffer(
			buff_size,
			{.UNIFORM_BUFFER},
			.AUTO,
			{.HOST_ACCESS_SEQUENTIAL_WRITE},
		)

	}

}

// @TODO use p_dt
vt_update_uniform_buffer :: proc() {
	using G_RENDERER
	using G_VT

	current_time := time.now()
	dt := f32(time.duration_seconds(time.diff(start_time, current_time)))


	ubo := UniformBufferObject {
		model = glsl.identity(
			glsl.mat4,
		) * glsl.mat4Rotate({0, 0, 1}, glsl.radians_f32(90.0) * dt),
		view  = glsl.mat4LookAt({0, 1, 2}, {0, 0, 0}, {0, 1, 0}),
		proj  = glsl.mat4Perspective(
			glsl.radians_f32(45.0),
			f32(swap_extent.width) / f32(swap_extent.height),
			0.1,
			10.0,
		),
	}

	ubo_data: rawptr
	vma.map_memory(vma_allocator, uniform_buffer_allocation[frame_idx], &ubo_data)
	mem.copy(ubo_data, &ubo, size_of(UniformBufferObject))
	vma.unmap_memory(vma_allocator, uniform_buffer_allocation[frame_idx])
}

vt_create_descriptor_pool :: proc() {
	using G_RENDERER
	using G_VT

	ubo_pool_size := vk.DescriptorPoolSize {
		type            = .UNIFORM_BUFFER,
		descriptorCount = num_frames_in_flight,
	}

	sampler_pool_size := vk.DescriptorPoolSize {
		type            = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = num_frames_in_flight,
	}


	pool_sizes := []vk.DescriptorPoolSize{ubo_pool_size, sampler_pool_size}


	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
		maxSets       = num_frames_in_flight,
	}

	if vk.CreateDescriptorPool(device, &pool_info, nil, &descriptor_pool) != .SUCCESS {
		log.warn("Failed to create descriptor pool")
	}
}

vk_create_descriptor_sets :: proc() {
	using G_RENDERER
	using G_VT

	resize(&descriptor_sets, int(num_frames_in_flight))

	set_layouts := make(
		[dynamic]vk.DescriptorSetLayout,
		int(num_frames_in_flight),
		context.allocator,
	)
	for _, i in set_layouts {
		set_layouts[i] = descriptor_set_layout
	}
	defer delete(set_layouts)

	descriptor_sets_alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor_pool,
		descriptorSetCount = num_frames_in_flight,
		pSetLayouts        = raw_data(set_layouts),
	}

	if vk.AllocateDescriptorSets(
		   device,
		   &descriptor_sets_alloc_info,
		   raw_data(descriptor_sets),
	   ) != .SUCCESS {
		log.warn("Failed to allocate descriptor sets")
	}
}

vt_write_descriptor_sets :: proc() {
	using G_RENDERER
	using G_VT

	ubo_info := vk.DescriptorBufferInfo {
		range = size_of(UniformBufferObject),
	}
	ubo_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = 0,
		descriptorCount = 1,
		descriptorType  = .UNIFORM_BUFFER,
		pBufferInfo     = &ubo_info,
	}

	image_info := vk.DescriptorImageInfo {
		sampler     = texture_sampler,
		imageLayout = .READ_ONLY_OPTIMAL,
		imageView   = texture_image_view,
	}

	image_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = 1,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &image_info,
	}


	for i in 0 ..< num_frames_in_flight {
		ubo_info.buffer = uniform_buffers[i]
		ubo_write.dstSet = descriptor_sets[i]
		image_write.dstSet = descriptor_sets[i]
		descriptor_writes := []vk.WriteDescriptorSet{ubo_write, image_write}

		vk.UpdateDescriptorSets(
			device,
			u32(len(descriptor_writes)),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}
}

vt_create_texture_image :: proc() {
	using G_RENDERER
	using G_VT

	image_width, image_height, channels: c.int
	pixels := stb_image.load(
		"app_data/renderer/assets/textures/texture.jpg",
		&image_width,
		&image_height,
		&channels,
		4,
	)

	if pixels == nil {
		log.debug("Failed to load image")
	}

	image_size := vk.DeviceSize(image_width * image_height * 4)

	staging_buffer, staging_buffer_alloc := vt_create_buffer(
		image_size,
		{.TRANSFER_SRC},
		.AUTO_PREFER_HOST,
		{.HOST_ACCESS_SEQUENTIAL_WRITE},
	)

	defer vma.destroy_buffer(vma_allocator, staging_buffer, staging_buffer_alloc)

	mapped_data: rawptr
	vma.map_memory(vma_allocator, staging_buffer_alloc, &mapped_data)
	mem.copy(mapped_data, pixels, int(image_size * size_of(u8)))
	vma.unmap_memory(vma_allocator, staging_buffer_alloc)

	stb_image.image_free(pixels)

	image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = u32(image_width), height = u32(image_height), depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		format = .R8G8B8A8_SRGB,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED,
		usage = {.TRANSFER_DST, .SAMPLED},
		sharingMode = .EXCLUSIVE,
		samples = {._1},
	}
	alloc_create_info := vma.AllocationCreateInfo {
		usage = .AUTO,
	}

	if vma.create_image(
		   vma_allocator,
		   &image_create_info,
		   &alloc_create_info,
		   &texture_image,
		   &texture_image_allocation,
		   nil,
	   ) != .SUCCESS {
		log.warn("Failed to create an image")
	}


	vt_transition_image_layout(texture_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	vt_copy_buffer_to_image(
		staging_buffer,
		texture_image,
		u32(image_width),
		u32(image_height),
	)
	vt_transition_image_layout(
		texture_image,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
	)
}


vt_begin_single_time_command_buffer :: proc() -> vk.CommandBuffer {
	using G_VT
	using G_RENDERER

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pools[0],
		commandBufferCount = 1,
	}
	cmd_buff: vk.CommandBuffer
	vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buff)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(cmd_buff, &begin_info)
	return cmd_buff
}

vt_end_single_time_command_buffer :: proc(cmd_buff: vk.CommandBuffer) {
	using G_VT
	using G_RENDERER

	vk.EndCommandBuffer(cmd_buff)

	command_buffer := cmd_buff
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}
	vk.QueueSubmit(graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(graphics_queue)
}

vt_transition_image_layout :: proc(
	p_image: vk.Image,
	p_old_layout: vk.ImageLayout,
	p_new_layout: vk.ImageLayout,
) {

	cmd_buff := vt_begin_single_time_command_buffer()
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = p_old_layout,
		newLayout = p_new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = p_image,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	src_stage: vk.PipelineStageFlags
	dst_stage: vk.PipelineStageFlags
	if p_old_layout == .UNDEFINED && p_new_layout == .TRANSFER_DST_OPTIMAL {
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.TRANSFER}
	} else if p_old_layout == .TRANSFER_DST_OPTIMAL && p_new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		src_stage = {.TRANSFER}
		dst_stage = {.FRAGMENT_SHADER}
	} else if p_old_layout == .UNDEFINED && p_new_layout == .DEPTH_ATTACHMENT_OPTIMAL {
		barrier.dstAccessMask = {
			.DEPTH_STENCIL_ATTACHMENT_READ,
			.DEPTH_STENCIL_ATTACHMENT_WRITE,
		}

		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.EARLY_FRAGMENT_TESTS}

	}
	vk.CmdPipelineBarrier(cmd_buff, src_stage, dst_stage, nil, 0, nil, 0, nil, 1, &barrier)
	vt_end_single_time_command_buffer(cmd_buff)

}

vt_copy_buffer_to_image :: proc(
	p_buffer: vk.Buffer,
	p_image: vk.Image,
	p_width: u32,
	p_height: u32,
) {
	cmd_buff := vt_begin_single_time_command_buffer()
	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {width = p_width, height = p_height, depth = 1},
	}
	vk.CmdCopyBufferToImage(cmd_buff, p_buffer, p_image, .TRANSFER_DST_OPTIMAL, 1, &region)
	vt_end_single_time_command_buffer(cmd_buff)
}

vt_create_texture_image_view :: proc() {
	G_VT.texture_image_view = vt_create_image_view(
		G_VT.texture_image,
		.R8G8B8A8_SRGB,
		{.COLOR},
	)
}

vt_create_image_view :: proc(
	p_image: vk.Image,
	p_format: vk.Format,
	p_aspect_mask: vk.ImageAspectFlags,
) -> vk.ImageView {
	using G_RENDERER
	using G_VT

	view_create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = p_image,
		viewType = .D2,
		format = p_format,
		subresourceRange = {aspectMask = p_aspect_mask, levelCount = 1, layerCount = 1},
	}

	image_view: vk.ImageView
	if vk.CreateImageView(device, &view_create_info, nil, &image_view) != .SUCCESS {
		log.warn("Failed to create image view")
	}
	return image_view
}

vt_create_texture_sampler :: proc() {
	using G_RENDERER
	using G_VT

	sampler_create_info := vk.SamplerCreateInfo {
		sType            = .SAMPLER_CREATE_INFO,
		magFilter        = .LINEAR,
		minFilter        = .LINEAR,
		addressModeU     = .REPEAT,
		addressModeV     = .REPEAT,
		addressModeW     = .REPEAT,
		anisotropyEnable = true,
		maxAnisotropy    = device_properties.limits.maxSamplerAnisotropy,
		borderColor      = .INT_OPAQUE_BLACK,
		compareOp        = .ALWAYS,
		mipmapMode       = .LINEAR,
	}

	if vk.CreateSampler(device, &sampler_create_info, nil, &texture_sampler) != .SUCCESS {
		log.warn("Failed to create sampler")
	}
}


vt_create_depth_resources :: proc() {
	using G_RENDERER
	using G_VT


	depth_image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = swap_extent.width, height = swap_extent.height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		format = .D32_SFLOAT,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED,
		usage = {.DEPTH_STENCIL_ATTACHMENT},
		sharingMode = .EXCLUSIVE,
		samples = {._1},
	}
	alloc_create_info := vma.AllocationCreateInfo {
		usage = .AUTO,
	}

	if vma.create_image(
		   vma_allocator,
		   &depth_image_create_info,
		   &alloc_create_info,
		   &depth_image,
		   &depth_image_allocation,
		   nil,
	   ) != .SUCCESS {
		log.warn("Failed to create an image")
	}

	depth_image_view = vt_create_image_view(depth_image, .D32_SFLOAT, {.DEPTH})
}
