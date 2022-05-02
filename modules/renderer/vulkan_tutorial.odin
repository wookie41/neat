package renderer

import "core:fmt"
import "core:math/linalg/glsl"
import "core:mem"
import "core:log"
import "core:time"

import vk "vendor:vulkan"
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
}

Vertex :: struct {
	position: glsl.vec2,
	color:    glsl.vec3,
}

vertex_binding_description := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

vertex_attributes_descriptions := []vk.VertexInputAttributeDescription{
	{binding = 0, location = 0, format = .R32G32_SFLOAT},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
}

g_vertices :: []Vertex{
	{{-0.5, -0.5}, {1.0, 0.0, 0.0}},
	{{0.5, -0.5}, {0.0, 1.0, 0.0}},
	{{0.5, 0.5}, {0.0, 0.0, 1.0}},
	{{-0.5, 0.5}, {1.0, 1.0, 1.0}},
}

g_indices :: []u16{0, 1, 2, 2, 3, 0}

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

	return true
}

deinit_vt :: proc() {
	using G_VT
	using G_RENDERER

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

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		colorAttachmentCount = 1,
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

	cmd := command_buffers[frame_idx]
	vk.BeginCommandBuffer(cmd, &cmd_buffer_begin_info)

	vt_update_uniform_buffer()

	vk.CmdBeginRendering(cmd, &rendering_info)
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

	offset := vk.DeviceSize{}

	vk.CmdBindPipeline(cmd, .GRAPHICS, pso)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer, &offset)
	vk.CmdBindIndexBuffer(cmd, index_buffer, offset, .UINT16)
	vk.CmdDrawIndexed(cmd, u32(len(g_indices)), 1, 0, 0, 0)
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

	vk.CmdEndRendering(cmd)
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
		return vk.BUFFER_NULL, nil
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

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pools[0],
		commandBufferCount = 1,
	}
	copy_cmd_buff: vk.CommandBuffer
	vk.AllocateCommandBuffers(device, &alloc_info, &copy_cmd_buff)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(copy_cmd_buff, &begin_info)

	copy_region := vk.BufferCopy {
		size = p_size,
	}
	vk.CmdCopyBuffer(copy_cmd_buff, p_src_buffer, p_dst_buffer, 1, &copy_region)
	vk.EndCommandBuffer(copy_cmd_buff)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &copy_cmd_buff,
	}
	vk.QueueSubmit(graphics_queue, 1, &submit_info, vk.FENCE_NULL)
	vk.QueueWaitIdle(graphics_queue)
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

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &ubo_layout_binding,
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
			{.UNIFORM_BUFFER },
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
	dt := f32(time.duration_milliseconds(time.diff(start_time, current_time)))

	
	ubo := UniformBufferObject{
		model = glsl.identity(glsl.mat4) * glsl.mat4Rotate({0, 0, 1}, glsl.radians_f32(90.0) * dt),
		view = glsl.mat4LookAt({2, 2, 2}, {0, 0, 0}, {0, 0, 1}),
		proj = glsl.mat4Perspective(glsl.radians_f32(45.0), f32(swap_extent.width) / f32(swap_extent.height), 0.1, 10.0),
	}

	ubo.proj[1][1] *= -1;

	ubo_data: rawptr
	vma.map_memory(vma_allocator, uniform_buffer_allocation[frame_idx], &ubo_data)
	mem.copy(ubo_data, &ubo, size_of(UniformBufferObject))
	vma.unmap_memory(vma_allocator, uniform_buffer_allocation[frame_idx])

}
