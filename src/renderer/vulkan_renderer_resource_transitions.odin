package renderer

//---------------------------------------------------------------------------//	

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//	

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//	

	backend_transition_resources :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_bindings: ^RenderPassBindings,
		p_pipeline_type: PipelineType,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_input_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(p_bindings.image_inputs),
			temp_arena.allocator,
		)

		image_input_barriers_count := 0

		// Prepare barriers for image inputs
		for input in p_bindings.image_inputs {

			image_idx := get_image_idx(input.image_ref)
			image := &g_resources.images[image_idx]

			input_usage := ImageUsage.SampledImage
			new_layout := vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
			dst_access_mask := vk.AccessFlags{.SHADER_READ}

			if .Storage in input.flags {
				dst_access_mask += {.SHADER_WRITE}
				new_layout = vk.ImageLayout.GENERAL
				input_usage = ImageUsage.General
			} else if image.desc.format > .DepthFormatsStart &&
			   image.desc.format < .DepthFormatsEnd {

				if image.desc.format > .DepthStencilFormatsStart &&
				   image.desc.format < .DepthStencilFormatsEnd {
					new_layout = vk.ImageLayout.DEPTH_STENCIL_READ_ONLY_OPTIMAL
				}
				new_layout = vk.ImageLayout.DEPTH_READ_ONLY_OPTIMAL
			}

			image_backend := &g_resources.backend_images[image_idx]

			old_layout := image_backend.vk_layout_per_mip[0]
			mip_count := image.desc.mip_count
			mip: u32 = 0

			if .AddressSubresource in input.flags {
				mip = u32(input.mip)
				old_layout = image_backend.vk_layout_per_mip[mip]
				mip_count = 1
			}

			// Check if this image needs to be transitioned
			if old_layout == new_layout {
				continue
			}

			image_input_barriers[image_input_barriers_count] = vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				dstAccessMask = dst_access_mask,
				oldLayout = old_layout,
				newLayout = new_layout,
				image = image_backend.vk_image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseArrayLayer = 0,
					layerCount = 1,
					baseMipLevel = mip,
					levelCount = u32(mip_count),
				},
			}

			image_backend.vk_layout_per_mip[mip] = new_layout

			image_input_barriers_count += 1
		}

        cmd_buffer_idx := get_cmd_buffer_idx(p_cmd_buff_ref)
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[cmd_buffer_idx]

		// Insert barriers for input
		if image_input_barriers_count > 0 {
			vk.CmdPipelineBarrier(
				backend_cmd_buffer.vk_cmd_buff,
				{.BOTTOM_OF_PIPE},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				{},
				0,
				nil,
				0,
				nil,
				u32(image_input_barriers_count),
				&image_input_barriers[0],
			)
		}

		if p_pipeline_type == .Compute {
			assert(
				len(p_bindings.image_outputs) == 0,
				"Output bindings are only supported for the graphics pipe",
			)
			return
		}

        // Now prepare output barriers
		image_output_barriers_count := 0
		image_output_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(p_bindings.image_outputs),
			temp_arena.allocator,
		)
		depth_barrier := vk.ImageMemoryBarrier{}
		depth_barrier_needed := false

		// Prepare barriers for outputs
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

			// Prepare the rendering attachment
			load_op := vk.AttachmentLoadOp.DONT_CARE
			if .Clear in output.flags {
				load_op = .CLEAR
			}

			new_layout := vk.ImageLayout{}
			if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {

				has_stencil_component :=
					image.desc.format > .DepthStencilFormatsStart &&
					image.desc.format < .DepthStencilFormatsEnd

				new_layout = vk.ImageLayout.DEPTH_ATTACHMENT_OPTIMAL
				if has_stencil_component {
					new_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
				}

				// Check if this image needs to be transitioned
				if image_backend.vk_layout_per_mip[output.mip] == new_layout {
					continue
				}

				depth_barrier_needed = true

				// Transition the depth buffer to the expected layout
				depth_barrier = {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {
						.DEPTH_STENCIL_ATTACHMENT_READ,
						.DEPTH_STENCIL_ATTACHMENT_WRITE,
					},
					oldLayout = image_backend.vk_layout_per_mip[output.mip],
					newLayout = new_layout,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = {.DEPTH},
						baseArrayLayer = 0,
						layerCount = 1,
						baseMipLevel = u32(output.mip),
						levelCount = 1,
					},
				}
			} else {

				new_layout = .ATTACHMENT_OPTIMAL

				// Check if this image needs to be transitioned
				if image_backend.vk_layout_per_mip[output.mip] == new_layout {
					continue
				}

				// Transition the image to the expected layout
				image_output_barriers[image_output_barriers_count] = {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
					oldLayout = image_backend.vk_layout_per_mip[output.mip],
					newLayout = new_layout,
					image = image_backend.vk_image,
					subresourceRange = {
						aspectMask = {.COLOR},
						baseArrayLayer = 0,
						layerCount = 1,
						baseMipLevel = u32(output.mip),
						levelCount = 1,
					},
				}
				image_output_barriers_count += 1

			}
			image_backend.vk_layout_per_mip[output.mip] = new_layout
		}

		// Insert depth attachment barrier
		if depth_barrier_needed {
			vk.CmdPipelineBarrier(
				backend_cmd_buffer.vk_cmd_buff,
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

		// Insert output barriers
		if image_output_barriers_count > 0 {
			vk.CmdPipelineBarrier(
				backend_cmd_buffer.vk_cmd_buff,
				{.TOP_OF_PIPE},
				{.COLOR_ATTACHMENT_OUTPUT},
				{},
				0,
				nil,
				0,
				nil,
				u32(image_output_barriers_count),
				&image_output_barriers[0],
			)
		}
	}

	//---------------------------------------------------------------------------//	    
}
