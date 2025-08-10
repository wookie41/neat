package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_command_execute :: proc(
		p_ref: DrawCommandRef,
		p_cmd_buff_ref: CommandBufferRef,
		p_pipeline_ref: GraphicsPipelineRef,
		p_push_constant: []rawptr,
	) {
		cmd_buff := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]

		pipeline_idx := get_graphics_pipeline_idx(p_pipeline_ref)
		pipeline := &g_resources.compute_pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_compute_pipelines[pipeline_idx]

		for push_constant, i in pipeline.desc.push_constants {
			vk.CmdPushConstants(
				cmd_buff.vk_cmd_buff,
				backend_pipeline.vk_pipeline_layout,
				{.COMPUTE},
				push_constant.offset_in_bytes,
				push_constant.size_in_bytes,
				p_push_constant[i],
			)
		}

		if draw_command.desc.vertex_buffer_ref != InvalidBufferRef {
			vertex_buffer_offset := vk.DeviceSize(draw_command.desc.vertex_buffer_offset)
			vertex_buffer := &g_resources.backend_buffers[buffer_get_idx(draw_command.desc.vertex_buffer_ref)]
			vk.CmdBindVertexBuffers(
				cmd_buff.vk_cmd_buff,
				0,
				1,
				&vertex_buffer.vk_buffer,
				&vertex_buffer_offset,
			)
		} else {
			vertex_buffer_offset := vk.DeviceSize(0)
			vertex_buffer: vk.Buffer = 0
			vk.CmdBindVertexBuffers(
				cmd_buff.vk_cmd_buff,
				0,
				1,
				&vertex_buffer,
				&vertex_buffer_offset,
			)
		}

		if draw_command.desc.index_buffer_ref == InvalidBufferRef {
			vk.CmdDraw(cmd_buff.vk_cmd_buff, draw_command.desc.draw_count, 1, 0, 0)
		} else {
			index_buffer := &g_resources.backend_buffers[buffer_get_idx(draw_command.desc.vertex_buffer_ref)]
			vk.CmdBindIndexBuffer(
				cmd_buff.vk_cmd_buff,
				index_buffer.vk_buffer,
				vk.DeviceSize(draw_command.desc.index_buffer_offset),
				.UINT32,
			)
			vk.CmdDrawIndexed(cmd_buff.vk_cmd_buff, draw_command.desc.draw_count, 1, 0, 0, 0)
		}
	}

	//---------------------------------------------------------------------------//

}
