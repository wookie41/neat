package renderer

//---------------------------------------------------------------------------//

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {}

	@(private)
	BackendRenderPassResource :: struct {}

	@(private)
	backend_init_render_passes :: proc() {
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_render_pass :: proc(p_ref: RenderPassRef) -> bool {
		return true
	}

	//---------------------------------------------------------------------------//	

	@(private)
	backend_destroy_render_pass :: proc(p_render_pass_ref: RenderPassRef) {
		// nothing to do
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_begin_render_pass :: proc(
		p_render_pass_ref: RenderPassRef,
		p_cmd_buff_ref: CommandBufferRef,
		p_begin_info: ^RenderPassBeginInfo,
	) {
		render_pass_idx := get_render_pass_idx(p_render_pass_ref)
		render_pass := &g_resources.render_passes[render_pass_idx]

		assert((.IsActive in render_pass.flags) == false)

		render_pass.flags += {.IsActive}

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_input_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(p_begin_info.interface.image_inputs),
			temp_arena.allocator,
		)

		image_input_barriers_count := 0

		// Prepare barriers for image inputs
		for input in p_begin_info.interface.image_inputs {

			image_idx := get_image_idx(input.image_ref)
			image := &g_resources.images[image_idx]

			input_usage := ImageUsage.SampledImage
			new_layout := vk.ImageLayout.ATTACHMENT_OPTIMAL
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
				mip = input.mip
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


		color_attachments_count := 0
		color_attachments := make(
			[]vk.RenderingAttachmentInfo,
			len(p_begin_info.interface.image_outputs),
			temp_arena.allocator,
		)
		depth_attachment := vk.RenderingAttachmentInfo{}

		image_output_barriers_count := 0
		image_output_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(p_begin_info.interface.image_outputs),
			temp_arena.allocator,
		)
		depth_attachment_barrier := vk.ImageMemoryBarrier{}

		has_depth_attachment := false
		depth_barrier_needed := false

		// Prepare barriers and rendering attachments for outputs
		for output in p_begin_info.interface.image_outputs {

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
			image_view := image_backend.per_mip_vk_view[output.mip]

			load_op := vk.AttachmentLoadOp.DONT_CARE
			if .Clear in output.flags {
				load_op = .CLEAR
			}

			dst_pipeline_flags := vk.PipelineStageFlags{}
			dst_access_mask := vk.AccessFlags{}
			new_layout := vk.ImageLayout{}
			aspect_mask := vk.ImageAspectFlags{}

			if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {

				assert(has_depth_attachment == false) // only 1 depth attachment allowed
				has_depth_attachment = true

				has_stencil_component :=
					image.desc.format > .DepthStencilFormatsStart &&
					image.desc.format < .DepthStencilFormatsEnd

				new_layout := vk.ImageLayout.DEPTH_ATTACHMENT_OPTIMAL
				if has_stencil_component {
					new_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
				}

				depth_attachment = {
					sType = .RENDERING_ATTACHMENT_INFO,
					pNext = nil,
					clearValue = {
						depthStencil = {
							depth = output.clear_color.x,
							stencil = u32(output.clear_color.y),
						},
					},
					imageLayout = new_layout,
					imageView = image_view,
					loadOp = load_op,
					storeOp = .STORE,
				}

				// Check if this image needs to be transitioned
				if image_backend.vk_layout_per_mip[output.mip] == new_layout {
					continue
				}

				depth_barrier_needed = true

				depth_attachment_barrier = {
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
						baseMipLevel = output.mip,
						levelCount = 1,
					},
				}
			} else {

				new_layout = .ATTACHMENT_OPTIMAL

				color_attachments[color_attachments_count] = {
					sType = .RENDERING_ATTACHMENT_INFO,
					pNext = nil,
					clearValue = {color = {float32 = cast([4]f32)output.clear_color}},
					imageLayout = new_layout,
					imageView = image_view,
					loadOp = load_op,
					storeOp = .STORE,
				}

				color_attachments_count += 1

				// Check if this image needs to be transitioned
				if image_backend.vk_layout_per_mip[output.mip] == new_layout {
					continue
				}

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
						baseMipLevel = output.mip,
						levelCount = 1,
					},
				}
				image_output_barriers_count += 1

			}
			image_backend.vk_layout_per_mip[output.mip] = new_layout
		}

		cmd_buffer_idx := get_cmd_buffer_idx(p_cmd_buff_ref)
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[cmd_buffer_idx]

		// Insert input barriers
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
				&depth_attachment_barrier,
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

		// Prepare the rendering info
		render_area := G_RENDERER.swap_extent

		#partial switch render_pass.desc.resolution {
		case .Half:
			render_area.width /= 2
			render_area.height /= 2
		case .Quarter:
			render_area.width /= 4
			render_area.height /= 4
		}

		rendering_info := vk.RenderingInfo {
			sType = .RENDERING_INFO,
			colorAttachmentCount = u32(color_attachments_count),
			layerCount = 1,
			viewMask = 0,
			pColorAttachments = &color_attachments[0],
			pDepthAttachment = &depth_attachment if has_depth_attachment else nil,
			renderArea = {extent = render_area},
		}

		viewport := vk.Viewport {
			x        = 0.0,
			y        = cast(f32)render_area.height,
			width    = cast(f32)render_area.width,
			height   = -cast(f32)render_area.height,
			minDepth = 0.0,
			maxDepth = 1.0,
		}

		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = render_area,
		}

		vk.CmdBeginRendering(backend_cmd_buffer.vk_cmd_buff, &rendering_info)
		vk.CmdSetViewport(backend_cmd_buffer.vk_cmd_buff, 0, 1, &viewport)
		vk.CmdSetScissor(backend_cmd_buffer.vk_cmd_buff, 0, 1, &scissor)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_end_render_pass :: #force_inline proc(
		p_render_pass_ref: RenderPassRef,
		p_cmd_buff_ref: CommandBufferRef,
	) {
		render_pass := &g_resources.render_passes[get_render_pass_idx(p_render_pass_ref)]
		assert(.IsActive in render_pass.flags)
		render_pass.flags -= {.IsActive}

		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		vk.CmdEndRendering(backend_cmd_buffer.vk_cmd_buff)
	}
}
