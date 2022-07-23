package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"
import log "core:log"
import "../common"

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
	backend_create_render_pass :: proc(
		p_render_pass_desc: RenderPassDesc,
		p_render_pass: ^RenderPassResource,
	) -> bool {

		render_target_formats := make(
			[]ImageFormat,
			len(p_render_pass_desc.render_target_infos),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for render_target_info, i in p_render_pass_desc.render_target_infos {
			render_target_formats[i] = render_target_info.format
		}

		pipeline_desc := PipelineDesc {
			name                      = p_render_pass_desc.name,
			vert_shader               = p_render_pass_desc.vert_shader,
			frag_shader               = p_render_pass_desc.frag_shader,
			vertex_layout             = p_render_pass_desc.vertex_layout,
			primitive_type            = p_render_pass_desc.primitive_type,
			multisampling_type        = p_render_pass_desc.multisampling_type,
			depth_stencil_type        = p_render_pass_desc.depth_stencil_type,
			render_target_formats     = render_target_formats,
			render_target_blend_types = p_render_pass_desc.render_target_blend_types,
			depth_format              = p_render_pass_desc.depth_format,
		}

		p_render_pass.pipeline = create_graphics_pipeline(pipeline_desc)
		if p_render_pass.pipeline == InvalidPipelineRef {
			log.warnf(
				"Failed to create the pipeline when initializing render pass: %s",
				common.get_name(p_render_pass_desc.name),
			)
			return false
		}

		return true
	}

	//---------------------------------------------------------------------------//	

	@(private)
	backend_destroy_render_pass :: proc(p_render_pass: ^RenderPassResource) {
		// nothing to do
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_begin_render_pass :: proc(
		p_render_pass_ref: RenderPassRef,
		p_cmd_buff_ref: CommandBufferRef,
		p_begin_info: ^RenderPassBeginInfo,
	) {
		render_pass := get_render_pass(p_render_pass_ref)
		assert((.IsActive in render_pass.flags) == false)

		render_pass.flags += {.IsActive}

		color_attachments := make(
			[]vk.RenderingAttachmentInfo,
			len(render_pass.desc.render_target_infos),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(color_attachments, G_RENDERER_ALLOCATORS.temp_allocator)

		num_render_target_barriers := 0
		render_target_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(render_pass.desc.render_target_infos),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(render_target_barriers, G_RENDERER_ALLOCATORS.temp_allocator)

		// Check compability of render targets, build the Vulkan color attachments and prepare barrier
		{
			render_target_index := 0
			for render_target_info in render_pass.desc.render_target_infos {

				binding_index := -1

				when ODIN_DEBUG {
					for binding, index in p_begin_info.render_targets_bindings {
						if common.name_equal(binding.name, render_target_info.name) {
							binding_index = index
							break
						}
					}

					assert(binding_index != -1, "Binding for render target not found")
				}

				render_target_binding := &p_begin_info.render_targets_bindings[binding_index]

				attachment_image := get_image(render_target_binding.target.image_ref)

				// Transition image to the .ATTACHMENT_OPTIMAL format if it's not already in one
				if render_target_binding.target.current_usage != .Attachment {

					old_layout := vk.ImageLayout.UNDEFINED

					if (.SwapImage in attachment_image.desc.flags) == false {
						#partial switch render_target_binding.target.current_usage {
						case .SampledImage:
							old_layout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
						}
					}

					render_target_barriers[num_render_target_barriers] = vk.ImageMemoryBarrier {
						sType = .IMAGE_MEMORY_BARRIER,
						dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
						oldLayout = old_layout,
						newLayout = .ATTACHMENT_OPTIMAL,
						image = attachment_image.vk_image,
						subresourceRange = {
							aspectMask = {.COLOR},
							baseArrayLayer = 0,
							layerCount = 1,
							baseMipLevel = u32(max(render_target_binding.target.image_mip, 0)),
							levelCount = 1,
						},
					}

					render_target_binding.target.current_usage = .Attachment
					num_render_target_barriers += 1
				}

				// Create the Vulkan attachment
				image_view := attachment_image.all_mips_vk_view
				if render_target_binding.target.image_mip > -1 {
					image_view = attachment_image.per_mip_vk_view[render_target_binding.target.image_mip]
				}
				color_attachments[render_target_index] = {
					sType = .RENDERING_ATTACHMENT_INFO,
					pNext = nil,
					clearValue = {
						color = {float32 = cast([4]f32)render_target_binding.target.clear_value},
					},
					imageLayout = .ATTACHMENT_OPTIMAL,
					imageView = image_view,
					loadOp = .CLEAR if .Clear in render_target_binding.target.flags else .DONT_CARE,
					storeOp = .STORE,
				}

				render_target_index += 1
			}
		}

		cmd_buff := get_command_buffer(p_cmd_buff_ref)

		// Prepare the depth attachment
		depth_attachment: vk.RenderingAttachmentInfo
		if p_begin_info.depth_attachment.image != InvalidImageRef {
			depth_image := get_image(p_begin_info.depth_attachment.image)
			assert(
				depth_image.desc.format >
				.DepthFormatsStart &&
				depth_image.desc.format <
				.DepthFormatsEnd,
			)

			// Depth attachment 
			depth_attachment = vk.RenderingAttachmentInfo {
				sType = .RENDERING_ATTACHMENT_INFO,
				pNext = nil,
				clearValue = {depthStencil = {depth = 1, stencil = 0}},
				imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
				imageView = depth_image.all_mips_vk_view,
				loadOp = .CLEAR,
				storeOp = .DONT_CARE,
			}

			// Check if the depth image requires any barriers
			if p_begin_info.depth_attachment.usage == .Undefined || p_begin_info.depth_attachment.usage ==
			   .SampledImage {

				depth_attachment_barrier := vk.ImageMemoryBarrier {
					sType = .IMAGE_MEMORY_BARRIER,
					dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE},
					oldLayout = .UNDEFINED,
					newLayout = .DEPTH_ATTACHMENT_OPTIMAL,
					image = depth_image.vk_image,
					subresourceRange = {
						aspectMask = {.DEPTH},
						baseArrayLayer = 0,
						layerCount = 1,
						baseMipLevel = 0,
						levelCount = 1,
					},
				}

				has_stencil_component := depth_image.desc.format > .DepthStencilFormatsStart && depth_image.desc.format <
                             .DepthStencilFormatsEnd

				if p_begin_info.depth_attachment.usage == .SampledImage {

					depth_attachment_barrier.srcAccessMask += {.SHADER_READ}
					depth_attachment_barrier.oldLayout = .DEPTH_READ_ONLY_OPTIMAL

					if has_stencil_component {
						depth_attachment_barrier.oldLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL
						depth_attachment_barrier.newLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
					}
				}

				if has_stencil_component {
					depth_attachment_barrier.subresourceRange.aspectMask += {.STENCIL}
				}

				vk.CmdPipelineBarrier(
					cmd_buff.vk_cmd_buff,
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

				p_begin_info.depth_attachment.usage = .Attachment
			}
		}


		// Insert the attachment barriers
		if len(render_target_barriers) > 0 {
			vk.CmdPipelineBarrier(
				cmd_buff.vk_cmd_buff,
				{.TOP_OF_PIPE},
				{.COLOR_ATTACHMENT_OUTPUT},
				{},
				0,
				nil,
				0,
				nil,
				u32(len(render_target_barriers)),
				&render_target_barriers[0],
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
			colorAttachmentCount = u32(len(color_attachments)),
			layerCount = 1,
			viewMask = 0,
			pColorAttachments = &color_attachments[0],
			pDepthAttachment = &depth_attachment if p_begin_info.depth_attachment.image != InvalidImageRef else nil,
			renderArea = {extent = render_area},
		}

		vk_pipeline := get_pipeline(render_pass.pipeline).vk_pipeline

		viewport := vk.Viewport {
			x        = 0.0,
			y        = 0.0,
			width    = cast(f32)render_area.width,
			height   = cast(f32)render_area.height,
			minDepth = 0.0,
			maxDepth = 1.0,
		}

		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = render_area,
		}

		vk.CmdBeginRendering(cmd_buff.vk_cmd_buff, &rendering_info)
		vk.CmdBindPipeline(cmd_buff.vk_cmd_buff, .GRAPHICS, vk_pipeline)
		vk.CmdSetViewport(cmd_buff.vk_cmd_buff, 0, 1, &viewport)
		vk.CmdSetScissor(cmd_buff.vk_cmd_buff, 0, 1, &scissor)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_end_render_pass :: #force_inline proc(
		p_render_pass_ref: RenderPassRef,
		p_cmd_buff_ref: CommandBufferRef,
	) {
		render_pass := get_render_pass(p_render_pass_ref)
		assert(.IsActive in render_pass.flags)
		render_pass.flags -= {.IsActive}


		cmd_buf := get_command_buffer(p_cmd_buff_ref)
		vk.CmdEndRendering(cmd_buf.vk_cmd_buff)
	}
}
