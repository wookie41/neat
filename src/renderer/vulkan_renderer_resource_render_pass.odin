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

		color_attachments_count := 0
		color_attachments := make(
			[]vk.RenderingAttachmentInfo,
			len(p_begin_info.bindings.image_outputs),
			temp_arena.allocator,
		)
		depth_attachment := vk.RenderingAttachmentInfo{}
		has_depth_attachment := false

		// Prepare rendering attachments for outputs
		for output in p_begin_info.bindings.image_outputs {

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

			new_layout := vk.ImageLayout{}
			if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {

				assert(has_depth_attachment == false) // only 1 depth attachment allowed
				has_depth_attachment = true

				has_stencil_component :=
					image.desc.format > .DepthStencilFormatsStart &&
					image.desc.format < .DepthStencilFormatsEnd

				new_layout = vk.ImageLayout.DEPTH_ATTACHMENT_OPTIMAL
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

				continue
			}

			// Handle color attachments
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

			image_backend.vk_layout_per_mip[output.mip] = new_layout
		}

		cmd_buffer_idx := get_cmd_buffer_idx(p_cmd_buff_ref)
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[cmd_buffer_idx]

		// Prepare the rendering info
		render_area := vk.Extent2D {
			width  = render_pass.desc.resolution.x,
			height = render_pass.desc.resolution.y,
		}

		if render_area.width == 0 || render_area.height == 0 {
			resolved_resolution := resolve_resolution(render_pass.desc.derived_resolution)
			render_area.width = resolved_resolution.x
			render_area.height = resolved_resolution.y
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

		// Setup render state
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
