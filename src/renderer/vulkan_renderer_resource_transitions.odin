package renderer

//---------------------------------------------------------------------------//	

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//	

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//	

	@(private)
	backend_transition_binding_resources :: proc(
		p_bindings: []Binding,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		input_image_barriers_graphics := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)
		input_image_barriers_compute := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)

		input_buffer_barriers_graphics := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)
		input_buffer_barriers_compute := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)

		output_image_barriers_graphics := make(
			[dynamic]vk.ImageMemoryBarrier,
			temp_arena.allocator,
		)
		output_image_barriers_compute := make([dynamic]vk.ImageMemoryBarrier, temp_arena.allocator)

		output_buffer_barriers_graphics := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)
		output_buffer_barriers_compute := make(
			[dynamic]vk.BufferMemoryBarrier,
			temp_arena.allocator,
		)

		depth_barrier := vk.ImageMemoryBarrier{}
		graphics_depth_barrier_needed := false
		compute_depth_barrier_needed := false

		dst_queue: DeviceQueueType = .Compute if p_async_compute else .Graphics

		for b in p_bindings {
			switch binding in b {
			case InputImageBinding:
				create_barrier_for_input_image(
					binding,
					p_pipeline_type,
					p_async_compute,
					dst_queue,
					&input_image_barriers_graphics,
					&input_image_barriers_compute,
				)

			case OutputImageBinding:
				create_barrier_for_output_image(
					binding,
					p_pipeline_type,
					p_async_compute,
					dst_queue,
					&output_image_barriers_graphics,
					&output_image_barriers_compute,
					&depth_barrier,
					&graphics_depth_barrier_needed,
					&compute_depth_barrier_needed,
				)

			case InputBufferBinding:
				create_barrier_for_input_buffer(
					binding,
					p_pipeline_type,
					p_async_compute,
					dst_queue,
					&input_buffer_barriers_graphics,
					&input_buffer_barriers_compute,
				)

			case OutputBufferBinding:
				create_barrier_for_output_buffer(
					binding,
					p_pipeline_type,
					p_async_compute,
					dst_queue,
					&output_buffer_barriers_graphics,
					&output_buffer_barriers_compute,
				)
			}
		}

		graphics_cmd_buff_ref := get_frame_cmd_buffer_ref()
		compute_cmd_buff := frame_compute_cmd_buffer_get()

		graphics_cmd_buffer_idx := command_buffer_get_idx(graphics_cmd_buff_ref)
		backend_graphics_cmd_buffer := &g_resources.backend_cmd_buffers[graphics_cmd_buffer_idx]

		// Insert barriers for input
		if len(input_image_barriers_graphics) > 0 || len(input_buffer_barriers_graphics) > 0 {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.COMPUTE_SHADER, .COLOR_ATTACHMENT_OUTPUT, .LATE_FRAGMENT_TESTS, .TRANSFER},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				{},
				0,
				nil,
				u32(len(input_buffer_barriers_graphics)),
				raw_data(input_buffer_barriers_graphics),
				u32(len(input_image_barriers_graphics)),
				raw_data(input_image_barriers_graphics),
			)
		}

		if len(input_image_barriers_compute) > 0 || len(input_buffer_barriers_compute) > 0 {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.BOTTOM_OF_PIPE},
				{},
				0,
				nil,
				u32(len(input_buffer_barriers_compute)),
				raw_data(input_buffer_barriers_compute),
				u32(len(input_image_barriers_compute)),
				raw_data(input_image_barriers_compute),
			)
		}

		// Insert depth attachment barrier
		if graphics_depth_barrier_needed {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.LATE_FRAGMENT_TESTS} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
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
				{.LATE_FRAGMENT_TESTS},
				{.COMPUTE_SHADER},
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
		if len(output_image_barriers_graphics) > 0 || len(output_buffer_barriers_graphics) > 0 {
			vk.CmdPipelineBarrier(
				backend_graphics_cmd_buffer.vk_cmd_buff,
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER, .TRANSFER, .COLOR_ATTACHMENT_OUTPUT},
				{.COLOR_ATTACHMENT_OUTPUT} if p_pipeline_type == .Graphics else {.COMPUTE_SHADER},
				{},
				0,
				nil,
				u32(len(output_buffer_barriers_graphics)),
				raw_data(output_buffer_barriers_graphics),
				u32(len(output_image_barriers_graphics)),
				raw_data(output_image_barriers_graphics),
			)
		}

		if len(output_image_barriers_compute) > 0 || len(output_buffer_barriers_compute) > 0 {
			vk.CmdPipelineBarrier(
				compute_cmd_buff,
				{.COMPUTE_SHADER},
				{.TOP_OF_PIPE},
				{},
				0,
				nil,
				u32(len(output_buffer_barriers_compute)),
				raw_data(output_buffer_barriers_compute),
				u32(len(output_image_barriers_compute)),
				raw_data(output_image_barriers_compute),
			)
		}
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
		p_binding: InputImageBinding,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_dst_queue: DeviceQueueType,
		p_graphics_barriers: ^[dynamic]vk.ImageMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.ImageMemoryBarrier,
	) {

		image_idx := image_get_idx(p_binding.image_ref)
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

		for array_layer in 0 ..< p_binding.array_layer_count {
			for mip in 0 ..< p_binding.mip_count {

				old_layout := image_backend.vk_layouts[array_layer][mip]

				if old_layout == new_layout {
					continue
				}

				image_input_barrier := vk.ImageMemoryBarrier {
					sType = .IMAGE_MEMORY_BARRIER,
					srcAccessMask = vk_resolve_access_from_layout(old_layout),
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

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_barrier_for_input_buffer :: proc(
		p_binding: InputBufferBinding,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_dst_queue: DeviceQueueType,
		p_graphics_barriers: ^[dynamic]vk.BufferMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.BufferMemoryBarrier,
	) {

		if p_binding.usage == .Uniform {
			return
		}

		buffer := &g_resources.buffers[buffer_get_idx(p_binding.buffer_ref)]
		backend_buffer := &g_resources.backend_buffers[buffer_get_idx(p_binding.buffer_ref)]

		if buffer.last_access == .Read {
			return
		}

		buffer_barrier := vk.BufferMemoryBarrier {
			sType               = .BUFFER_MEMORY_BARRIER,
			buffer              = backend_buffer.vk_buffer,
			dstAccessMask       = {.SHADER_READ},
			offset              = vk.DeviceSize(p_binding.offset),
			dstQueueFamilyIndex = get_queue_family_index(p_dst_queue),
			size                = vk.DeviceSize(
				buffer.desc.size if p_binding.size == 0 else p_binding.size,
			),
			srcQueueFamilyIndex = get_queue_family_index(buffer.queue),
		}

		buffer.last_access = .Read

		if p_async_compute {
			assert(p_pipeline_type == .Compute)
			append(p_compute_barriers, buffer_barrier)

			if buffer_barrier.srcAccessMask != buffer_barrier.dstAccessMask {
				append(p_graphics_barriers, buffer_barrier)
			}
		} else {
			if p_pipeline_type == .Graphics {
				append(p_graphics_barriers, buffer_barrier)
			}
		}

		buffer.queue = p_dst_queue
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_barrier_for_output_image :: proc(
		p_binding: OutputImageBinding,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_dst_queue: DeviceQueueType,
		p_graphics_barriers: ^[dynamic]vk.ImageMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.ImageMemoryBarrier,
		p_depth_barrier: ^vk.ImageMemoryBarrier,
		p_graphics_depth_barrier_needed: ^bool,
		p_compute_depth_barrier_needed: ^bool,
	) {

		image_idx := image_get_idx(p_binding.image_ref)
		image := &g_resources.images[image_idx]

		// Grab the proper swap image for this frame
		if .SwapImage in image.desc.flags {
			swap_image_ref := G_RENDERER.swap_image_refs[G_RENDERER.swap_img_idx]
			image_idx = image_get_idx(swap_image_ref)
			image = &g_resources.images[image_idx]
		}

		image_backend := &g_resources.backend_images[image_idx]

		new_layout: vk.ImageLayout = .GENERAL

		if p_pipeline_type == .Compute {

			is_depth_image :=
				image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd

			aspect_mask: vk.ImageAspectFlags = {.DEPTH} if is_depth_image else {.COLOR}
			old_layout := image_backend.vk_layouts[p_binding.array_layer][p_binding.base_mip]

			image_barrier := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				dstAccessMask = {.SHADER_WRITE},
				srcAccessMask = vk_resolve_access_from_layout(old_layout),
				oldLayout = old_layout,
				newLayout = new_layout,
				image = image_backend.vk_image,
				subresourceRange = {
					aspectMask = aspect_mask,
					baseArrayLayer = u32(p_binding.array_layer),
					layerCount = 1,
					baseMipLevel = u32(p_binding.base_mip),
					levelCount = u32(p_binding.mip_count),
				},
				srcQueueFamilyIndex = get_queue_family_index(image.queue),
				dstQueueFamilyIndex = get_queue_family_index(p_dst_queue),
			}

			insert_async_compute_barriers(
				image_barrier,
				p_pipeline_type,
				p_async_compute,
				p_graphics_barriers,
				p_compute_barriers,
			)

			image.queue = p_dst_queue

		} else if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {

			has_stencil_component :=
				image.desc.format > .DepthStencilFormatsStart &&
				image.desc.format < .DepthStencilFormatsEnd

			new_layout = vk.ImageLayout.DEPTH_ATTACHMENT_OPTIMAL
			if has_stencil_component {
				new_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
			}

			// Check if this image needs to be transitioned
			current_layout := image_backend.vk_layouts[p_binding.array_layer][p_binding.base_mip]
			if current_layout == new_layout {
				return
			}

			p_graphics_depth_barrier_needed^ = true

			// Transition the depth buffer to the expected layout
			p_depth_barrier^ = {
				sType = .IMAGE_MEMORY_BARRIER,
				dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE},
				srcAccessMask = vk_resolve_access_from_layout(current_layout),
				oldLayout = image_backend.vk_layouts[p_binding.array_layer][p_binding.base_mip],
				newLayout = new_layout,
				image = image_backend.vk_image,
				subresourceRange = {
					aspectMask = {.DEPTH},
					baseArrayLayer = u32(p_binding.array_layer),
					layerCount = 1,
					baseMipLevel = u32(p_binding.base_mip),
					levelCount = u32(p_binding.mip_count),
				},
				srcQueueFamilyIndex = get_queue_family_index(image.queue),
				dstQueueFamilyIndex = get_queue_family_index(.Graphics),
			}

			p_compute_depth_barrier_needed^ = image.queue != .Graphics
			image.queue = .Graphics
		} else {

			new_layout = .ATTACHMENT_OPTIMAL
			current_layout := image_backend.vk_layouts[p_binding.array_layer][p_binding.base_mip]

			if new_layout == current_layout {
				return
			}

			// Transition the image to the expected layout
			image_barrier := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
				oldLayout = current_layout,
				srcAccessMask = vk_resolve_access_from_layout(current_layout),
				newLayout = new_layout,
				image = image_backend.vk_image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseArrayLayer = u32(p_binding.array_layer),
					layerCount = 1,
					baseMipLevel = u32(p_binding.base_mip),
					levelCount = u32(p_binding.mip_count),
				},
				srcQueueFamilyIndex = get_queue_family_index(image.queue),
				dstQueueFamilyIndex = get_queue_family_index(.Graphics),
			}

			append(p_graphics_barriers, image_barrier)
			if image.queue != .Graphics {
				append(p_compute_barriers, image_barrier)
			}

			image.queue = .Graphics
		}

		for i in p_binding.base_mip ..< p_binding.mip_count {
			image_backend.vk_layouts[p_binding.array_layer][i] = new_layout
		}
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	create_barrier_for_output_buffer :: proc(
		p_binding: OutputBufferBinding,
		p_pipeline_type: PipelineType,
		p_async_compute: bool,
		p_dst_queue: DeviceQueueType,
		p_graphics_barriers: ^[dynamic]vk.BufferMemoryBarrier,
		p_compute_barriers: ^[dynamic]vk.BufferMemoryBarrier,
	) {
		buffer := &g_resources.buffers[buffer_get_idx(p_binding.buffer_ref)]
		backend_buffer := &g_resources.backend_buffers[buffer_get_idx(p_binding.buffer_ref)]

		buffer_barrier := vk.BufferMemoryBarrier {
			sType               = .BUFFER_MEMORY_BARRIER,
			buffer              = backend_buffer.vk_buffer,
			dstAccessMask       = {.SHADER_WRITE},
			offset              = vk.DeviceSize(p_binding.offset),
			dstQueueFamilyIndex = get_queue_family_index(p_dst_queue),
			size                = vk.DeviceSize(
				buffer.desc.size if p_binding.size == 0 else p_binding.size,
			),
			srcQueueFamilyIndex = get_queue_family_index(buffer.queue),
		}

		// if p_binding.needs_read_barrier {
		// 	buffer_barrier.srcAccessMask = {.SHADER_WRITE}
		// 	buffer_barrier.dstAccessMask += {.SHADER_READ}
		// }

		if p_async_compute {
			assert(p_pipeline_type == .Compute)
			append(p_compute_barriers, buffer_barrier)

			if buffer_barrier.srcAccessMask != buffer_barrier.dstAccessMask {
				append(p_graphics_barriers, buffer_barrier)
			}
		} else {
			append(p_graphics_barriers, buffer_barrier)
		}

		buffer.queue = p_dst_queue
		buffer.last_access = .Write
	}

	//---------------------------------------------------------------------------//

	@(private)
	vk_resolve_access_from_layout :: proc(p_image_layout: vk.ImageLayout) -> vk.AccessFlags {

		if p_image_layout == .GENERAL {
			return {.SHADER_WRITE}
		}

		if p_image_layout == .ATTACHMENT_OPTIMAL {
			return {.COLOR_ATTACHMENT_WRITE}
		}

		if p_image_layout == .DEPTH_ATTACHMENT_OPTIMAL {
			return {.DEPTH_STENCIL_ATTACHMENT_WRITE}
		}

		if p_image_layout == .TRANSFER_SRC_OPTIMAL {
			return {.TRANSFER_READ}
		}

		if p_image_layout == .TRANSFER_DST_OPTIMAL {
			return {.TRANSFER_WRITE}
		}

		if p_image_layout == .SHADER_READ_ONLY_OPTIMAL {
			return {.SHADER_READ}
		}

		if p_image_layout == .UNDEFINED || p_image_layout == .PRESENT_SRC_KHR {
			return {}
		}

		if p_image_layout == .DEPTH_READ_ONLY_OPTIMAL {
			return {.DEPTH_STENCIL_ATTACHMENT_READ}
		}

		assert(false)

		return {}
	}

}
