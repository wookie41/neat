package renderer

//---------------------------------------------------------------------------//	

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//	

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//	

	backend_transition_render_pass_resources :: proc(
		p_bindings: RenderPassBindings,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_input_barriers_graphics := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		image_input_barriers_compute := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)

		dst_queue: DeviceQueueType = .Compute if p_async_compute else .Graphics

		// Prepare barriers for image inputs
		for input in p_bindings.image_inputs {
			create_barrier_for_input_image(
				input,
				p_pipeline_type,
				p_async_compute,
				dst_queue,
				&image_input_barriers_graphics,
				&image_input_barriers_compute,
			)
		}
		for input in p_bindings.global_image_inputs {
			create_barrier_for_input_image(
				input,
				p_pipeline_type,
				p_async_compute,
				dst_queue,
				&image_input_barriers_graphics,
				&image_input_barriers_compute,
			)
		}

		// Input buffer barriers
		buffer_input_barriers_graphics := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)
		buffer_input_barriers_compute := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)

		for buffer_input in p_bindings.buffer_inputs {

			if buffer_input.usage == .Uniform {
				continue
			}

			buffer := &g_resources.buffers[buffer_get_idx(buffer_input.buffer_ref)]
			backend_buffer := &g_resources.backend_buffers[buffer_get_idx(buffer_input.buffer_ref)]

			if buffer.last_access == .Read {
				continue
			}

			buffer_barrier := vk.BufferMemoryBarrier {
				sType               = .BUFFER_MEMORY_BARRIER,
				buffer              = backend_buffer.vk_buffer,
				dstAccessMask       = {.SHADER_READ},
				offset              = vk.DeviceSize(buffer_input.offset),
				dstQueueFamilyIndex = get_queue_family_index(dst_queue),
				size                = vk.DeviceSize(
					buffer.desc.size if buffer_input.size == 0 else buffer_input.size,
				),
				srcQueueFamilyIndex = get_queue_family_index(buffer.queue),
			}

			buffer.last_access = .Read

			if p_async_compute {
				assert(p_pipeline_type == .Compute)
				append(&buffer_input_barriers_compute, buffer_barrier)

				if buffer_barrier.srcAccessMask != buffer_barrier.dstAccessMask {
					append(&buffer_input_barriers_graphics, buffer_barrier)
				}
			} else {
				append(&buffer_input_barriers_graphics, buffer_barrier)
			}

			buffer.queue = dst_queue
		}

		graphics_cmd_buff_ref := get_frame_cmd_buffer_ref()
		compute_cmd_buff := frame_compute_cmd_buffer_get()

		graphics_cmd_buffer_idx := command_buffer_get_idx(graphics_cmd_buff_ref)
		backend_graphics_cmd_buffer := &g_resources.backend_cmd_buffers[graphics_cmd_buffer_idx]

		// Insert barriers for input
		if len(image_input_barriers_graphics) > 0 || len(buffer_input_barriers_graphics) > 0{
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.BOTTOM_OF_PIPE},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				{},
				0,
				nil,
				u32(len(buffer_input_barriers_graphics)),
				raw_data(buffer_input_barriers_graphics),
				u32(len(image_input_barriers_graphics)),
				raw_data(image_input_barriers_graphics),
			)
		}

		if len(image_input_barriers_compute) > 0 || len(buffer_input_barriers_compute) > 0{
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.BOTTOM_OF_PIPE},
				{},
				0,
				nil,
				u32(len(buffer_input_barriers_compute)),
				raw_data(buffer_input_barriers_compute),
				u32(len(image_input_barriers_compute)),
				raw_data(image_input_barriers_compute),
			)
		}

		// Now prepare output image barriers
		image_output_barriers_graphics := make(
			[dynamic]vk.ImageMemoryBarrier,
			temp_arena.allocator,
		)
		image_output_barriers_compute := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		depth_barrier := vk.ImageMemoryBarrier{}
		graphics_depth_barrier_needed := false
		compute_depth_barrier_needed := false

		for output in p_bindings.image_outputs {

			image_idx := image_get_idx(output.image_ref)
			image := &g_resources.images[image_idx]

			// Grab the proper swap image for this frame
			if .SwapImage in image.desc.flags {
				swap_image_ref := G_RENDERER.swap_image_refs[G_RENDERER.swap_img_idx]
				image_idx = image_get_idx(swap_image_ref)
				image = &g_resources.images[image_idx]
			}

			image_backend := &g_resources.backend_images[image_idx]

			new_layout := vk.ImageLayout{}

			if p_pipeline_type == .Compute {

				// Check if this image needs to be transitioned
				if image_backend.vk_layouts[output.array_layer][output.mip] == .GENERAL {
					continue
				}

				is_depth_image :=
					image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd

				aspect_mask: vk.ImageAspectFlags = {.DEPTH} if is_depth_image else {.COLOR}

				image_barrier := vk.ImageMemoryBarrier {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {.SHADER_WRITE},
					oldLayout = image_backend.vk_layouts[output.array_layer][output.mip],
					newLayout = .GENERAL,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = aspect_mask,
						baseArrayLayer = u32(output.array_layer),
						layerCount = 1,
						baseMipLevel = u32(output.mip),
						levelCount = 1,
					},
					srcQueueFamilyIndex = get_queue_family_index(image.queue),
					dstQueueFamilyIndex = get_queue_family_index(dst_queue),
				}

				insert_async_compute_barriers(
					image_barrier,
					p_pipeline_type,
					p_async_compute,
					&image_output_barriers_graphics,
					&image_output_barriers_compute,
				)

				image.queue = dst_queue

			} else if image.desc.format > .DepthFormatsStart &&
			   image.desc.format < .DepthFormatsEnd {

				has_stencil_component :=
					image.desc.format > .DepthStencilFormatsStart &&
					image.desc.format < .DepthStencilFormatsEnd

				new_layout = vk.ImageLayout.DEPTH_ATTACHMENT_OPTIMAL
				if has_stencil_component {
					new_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
				}

				// Check if this image needs to be transitioned
				if image_backend.vk_layouts[output.array_layer][output.mip] == new_layout {
					continue
				}

				graphics_depth_barrier_needed = true

				// Transition the depth buffer to the expected layout
				depth_barrier = {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {
						.DEPTH_STENCIL_ATTACHMENT_READ,
						.DEPTH_STENCIL_ATTACHMENT_WRITE,
					},
					oldLayout = image_backend.vk_layouts[output.array_layer][output.mip],
					newLayout = new_layout,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = {.DEPTH},
						baseArrayLayer = u32(output.array_layer),
						layerCount = 1,
						baseMipLevel = u32(output.mip),
						levelCount = 1,
					},
					srcQueueFamilyIndex = get_queue_family_index(image.queue),
					dstQueueFamilyIndex = get_queue_family_index(.Graphics),
				}

				compute_depth_barrier_needed = image.queue != .Graphics
				image.queue = .Graphics
			} else {

				new_layout = .ATTACHMENT_OPTIMAL

				// Check if this image needs to be transitioned
				if image_backend.vk_layouts[output.array_layer][output.mip] == new_layout {
					continue
				}

				// Transition the image to the expected layout
				image_barrier := vk.ImageMemoryBarrier {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
					oldLayout = image_backend.vk_layouts[output.array_layer][output.mip],
					newLayout = new_layout,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = {.COLOR},
						baseArrayLayer = u32(output.array_layer),
						layerCount = 1,
						baseMipLevel = u32(output.mip),
						levelCount = 1,
					},
					srcQueueFamilyIndex = get_queue_family_index(image.queue),
					dstQueueFamilyIndex = get_queue_family_index(.Graphics),
				}

				append(&image_output_barriers_graphics, image_barrier)
				if image.queue != .Graphics {
					append(&image_output_barriers_compute, image_barrier)
				}

				image.queue = .Graphics
			}

			image_backend.vk_layouts[output.array_layer][output.mip] = new_layout
		}

		// Input buffer barriers
		buffer_output_barriers_graphics := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)
		buffer_output_barriers_compute := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)

		for buffer_output in p_bindings.buffer_outputs {

			buffer := &g_resources.buffers[buffer_get_idx(buffer_output.buffer_ref)]
			backend_buffer := &g_resources.backend_buffers[buffer_get_idx(buffer_output.buffer_ref)]

			buffer_barrier := vk.BufferMemoryBarrier {
				sType               = .BUFFER_MEMORY_BARRIER,
				buffer              = backend_buffer.vk_buffer,
				dstAccessMask       = {.SHADER_WRITE},
				offset              = vk.DeviceSize(buffer_output.offset),
				dstQueueFamilyIndex = get_queue_family_index(dst_queue),
				size                = vk.DeviceSize(
					buffer.desc.size if buffer_output.size == 0 else buffer_output.size,
				),
				srcQueueFamilyIndex = get_queue_family_index(buffer.queue),
			}

			if buffer_output.needs_read_barrier {
				buffer_barrier.srcAccessMask = {.SHADER_WRITE}
				buffer_barrier.dstAccessMask += {.SHADER_READ}
			}

			if p_async_compute {
				assert(p_pipeline_type == .Compute)
				append(&buffer_output_barriers_compute, buffer_barrier)

				if buffer_barrier.srcAccessMask != buffer_barrier.dstAccessMask {
					append(&buffer_output_barriers_graphics, buffer_barrier)
				}
			} else {
				append(&buffer_output_barriers_graphics, buffer_barrier)
			}

			buffer.queue = dst_queue
			buffer.last_access = .Write
		}

		// Insert depth attachment barrier
		if graphics_depth_barrier_needed {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.TOP_OF_PIPE} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{.EARLY_FRAGMENT_TESTS},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&depth_barrier,
			)
		}

		if compute_depth_barrier_needed {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.BOTTOM_OF_PIPE} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{.EARLY_FRAGMENT_TESTS},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&depth_barrier,
			)
		}

		// Insert output barriers
		if len(image_output_barriers_graphics) > 0 || len(buffer_output_barriers_graphics) > 0 {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.TOP_OF_PIPE} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{.COLOR_ATTACHMENT_OUTPUT} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{},
				0,
				nil,
				u32(len(buffer_output_barriers_graphics)),
				raw_data(buffer_output_barriers_graphics),
				u32(len(image_output_barriers_graphics)),
				raw_data(image_output_barriers_graphics),
			)
		}

		if len(image_output_barriers_compute) > 0 || len(buffer_output_barriers_compute) > 0 {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.TOP_OF_PIPE},
				{},
				0,
				nil,
				u32(len(buffer_output_barriers_compute)),
				raw_data(buffer_output_barriers_compute),
				u32(len(image_output_barriers_compute)),
				raw_data(image_output_barriers_compute),
			)
		}
	}

	//---------------------------------------------------------------------------//	

	backend_insert_barriers :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_image_barriers: []ImageBarrier,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		// TODO

		assert(false)
	}


	//---------------------------------------------------------------------------//	    

	@(private = "file")
	insert_async_compute_barriers :: proc(
		p_image_barrier: vk.ImageMemoryBarrier,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_graphics_barriers: ^[dynamic]vk.ImageMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.ImageMemoryBarrier,
	) {

		if p_async_compute {

			assert(p_pipeline_type == .Compute)
			append(p_compute_barriers, p_image_barrier)

			if p_image_barrier.srcAccessMask != p_image_barrier.dstAccessMask {
				append(p_graphics_barriers, p_image_barrier)
			}

			return
		}

		append(p_graphics_barriers, p_image_barrier)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_barrier_for_input_image :: proc(
		p_input_image: RenderPassImageInput,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_dst_queue: DeviceQueueType,
		p_graphics_barriers: ^[dynamic]vk.ImageMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.ImageMemoryBarrier,
	) {
		image_idx := image_get_idx(p_input_image.image_ref)
		image := &g_resources.images[image_idx]

		new_layout := vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
		dst_access_mask := vk.AccessFlags{.SHADER_READ}
		aspect_mask := vk.ImageAspectFlags{.COLOR}

		if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {

			aspect_mask = {.DEPTH}
			new_layout = .DEPTH_READ_ONLY_OPTIMAL

			if image.desc.format > .DepthStencilFormatsStart &&
			   image.desc.format < .DepthStencilFormatsEnd {
				new_layout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL
			}
		}

		image_backend := &g_resources.backend_images[image_idx]

		for array_layer in 0 ..< p_input_image.array_layer_count {
			for mip in 0 ..< p_input_image.mip_count {

				old_layout := image_backend.vk_layouts[array_layer][mip]

				if old_layout == new_layout {
					continue
				}

				image_input_barrier := vk.ImageMemoryBarrier {
					sType = .IMAGE_MEMORY_BARRIER,
					srcAccessMask = { .SHADER_WRITE },
					dstAccessMask = dst_access_mask,
					oldLayout = old_layout,
					newLayout = new_layout,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = aspect_mask,
						baseArrayLayer = array_layer,
						layerCount = 1,
						baseMipLevel = mip,
						levelCount = 1,
					},
				}

				if p_async_compute {
					image_input_barrier.srcQueueFamilyIndex = get_queue_family_index(image.queue)
					image_input_barrier.dstQueueFamilyIndex = get_queue_family_index(p_dst_queue)
				}

				image.queue = p_dst_queue

				insert_async_compute_barriers(
					image_input_barrier,
					p_pipeline_type,
					p_async_compute,
					p_graphics_barriers,
					p_compute_barriers,
				)

				image_backend.vk_layouts[array_layer][mip] = new_layout
			}
		}
	}
}
