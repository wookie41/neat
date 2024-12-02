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

		graphics_input_barriers := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		compute_input_barriers := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)

		dst_queue: DeviceQueueType = .Compute if p_async_compute else .Graphics

		// Prepare barriers for image inputs
		for input in p_bindings.image_inputs {
			create_barrier_for_input_image(
				input,
				p_pipeline_type,
				p_async_compute,
				dst_queue,
				&graphics_input_barriers,
				&compute_input_barriers,
			)
		}
		for input in p_bindings.global_image_inputs {
			create_barrier_for_input_image(
				input,
				p_pipeline_type,
				p_async_compute,
				dst_queue,
				&graphics_input_barriers,
				&compute_input_barriers,
			)
		}

		graphics_cmd_buff_ref := get_frame_cmd_buffer_ref()
		compute_cmd_buff := get_frame_compute_cmd_buffer()

		graphics_cmd_buffer_idx := get_cmd_buffer_idx(graphics_cmd_buff_ref)
		backend_graphics_cmd_buffer := &g_resources.backend_cmd_buffers[graphics_cmd_buffer_idx]

		// Insert barriers for input
		if len(graphics_input_barriers) > 0 {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.BOTTOM_OF_PIPE},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				{},
				0,
				nil,
				0,
				nil,
				u32(len(graphics_input_barriers)),
				&graphics_input_barriers[0],
			)
		}

		if len(compute_input_barriers) > 0 {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.BOTTOM_OF_PIPE},
				{},
				0,
				nil,
				0,
				nil,
				u32(len(compute_input_barriers)),
				&compute_input_barriers[0],
			)
		}

		// Now prepare output image barriers
		graphics_output_barriers := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		compute_output_barriers := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		depth_barrier := vk.ImageMemoryBarrier{}
		graphics_depth_barrier_needed := false
		compute_depth_barrier_needed := false

		for output in p_bindings.image_outputs {

			image_idx := get_image_idx(output.image_ref)
			image := &g_resources.images[image_idx]

			// Grab the proper swap image for this frame
			if .SwapImage in image.desc.flags {
				swap_image_ref := G_RENDERER.swap_image_refs[G_RENDERER.swap_img_idx]
				image_idx = get_image_idx(swap_image_ref)
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
					&graphics_output_barriers,
					&compute_output_barriers,
				)

				image.queue = .Compute

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

				append(&graphics_output_barriers, image_barrier)
				if image.queue != .Graphics {
					append(&compute_output_barriers, image_barrier)
				}

				image.queue = .Graphics
			}

			image_backend.vk_layouts[output.array_layer][output.mip] = new_layout
		}

		// @TODO Buffers

		// Insert depth attachment barrier
		if graphics_depth_barrier_needed {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.TOP_OF_PIPE},
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
				{.BOTTOM_OF_PIPE},
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
		if len(graphics_output_barriers) > 0 {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.TOP_OF_PIPE},
				{.COLOR_ATTACHMENT_OUTPUT} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{},
				0,
				nil,
				0,
				nil,
				u32(len(graphics_output_barriers)),
				&graphics_output_barriers[0],
			)
		}

		if len(compute_output_barriers) > 0 {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.TOP_OF_PIPE},
				{},
				0,
				nil,
				0,
				nil,
				u32(len(compute_output_barriers)),
				&compute_output_barriers[0],
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
		image_idx := get_image_idx(p_input_image.image_ref)
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
