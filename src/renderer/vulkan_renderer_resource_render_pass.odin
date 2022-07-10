package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"
import log "core:log"
import "../common"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

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

		color_attachment_formats := make(
			[]ImageFormat,
			len(p_render_pass_desc.color_attachment_formats),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(color_attachment_formats)

		{
			i := 0
			for _, format in p_render_pass_desc.color_attachment_formats {
				color_attachment_formats[i] = format
				i += 1
			}
		}

		pipeline_desc := PipelineDesc {
			name                     = p_render_pass_desc.name,
			vert_shader              = p_render_pass_desc.vert_shader,
			frag_shader              = p_render_pass_desc.frag_shader,
			vertex_layout            = p_render_pass_desc.vertex_layout,
			primitive_type           = p_render_pass_desc.primitive_type,
			multisampling_type       = p_render_pass_desc.multisampling_type,
			depth_stencil_type       = p_render_pass_desc.depth_stencil_type,
			color_attachment_formats = p_render_pass_desc.color_attachment_formats,
			color_blend_types        = p_render_pass_desc.color_blend_types,
			depth_format             = p_render_pass_desc.depth_format,
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
	backend_begin_render_pass :: proc(
		p_render_pass_ref: RenderPassRef,
		p_cmd_buff_ref: CommandBufferRef,
		p_begin_info: RenderPassBeginInfo,
	) {

		render_pass := get_render_pass(p_render_pass_ref)

		color_attachments := make(
			[]vk.RenderingAttachmentInfo,
			len(render_pass.desc.color_attachment_formats),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(color_attachments)

		// Check compability of color attachments and build the Vulkan attachments
		{
			i := 0
			for attachment_name, expected_format in render_pass.desc.color_attachment_formats {
				attachment_info, attachment_found := p_begin_info.color_attachments[attachment_name]
				if attachment_found == false {
					log.warnf(
						"No target found for color attachment %s when trying to begin render pass %s",
						common.get_name(attachment_name),
						common.get_name(render_pass.desc.name),
					)
					return
				}

				// @TODO transition image to the .ATTACHMENT_OPTIMAL format
				attachment_image := get_image(attachment_image_ref)

				color_attachments[i] = {
					sType = .RENDERING_ATTACHMENT_INFO,
					pNext = nil,
					clearValue = {color = {float32 = attachment_info.clear_value }},
					imageLayout = .ATTACHMENT_OPTIMAL,
					imageView = attachment_image.per_mip_vk_view[attachment_info.image_mip_level],
					loadOp = .CLEAR if .Clear in attachment_info.flags else .DONT_CARE,
					storeOp = .STORE,
				}

				i += 1
			}
		}

		// Depth attachment
		rendering_info := vk.RenderingInfo {
			sType = .RENDERING_INFO,
			colorAttachmentCount = 1,
			pDepthAttachment =  &depth_attachment
			layerCount = 1,
			viewMask = 0,
			pColorAttachments = &color_attachment,
			renderArea = {extent = G_RENDERER.swap_extent},
		}

	}
}
