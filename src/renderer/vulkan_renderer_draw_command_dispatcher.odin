package renderer
//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	INDEX_TYPE_MAPPING := []vk.IndexType {
		.UINT16,
		.UINT32,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_dispatch_draw_cmd :: #force_inline proc(
		p_draw_stream: ^DrawStream,
		p_cmd_buff: ^CommandBufferResource,
		p_draw_info: ^DrawInfo,
	) {
		vertex_buffer := get_buffer(p_draw_info.vertex_buffer_ref).vk_buffer
		vertex_buffer_offset := vk.DeviceSize(p_draw_info.vertex_buffer_offset)

		vk.CmdBindVertexBuffers(
			p_cmd_buff.vk_cmd_buff,
			0,
			1,
			&vertex_buffer,
			&vertex_buffer_offset,
		)
		vk.CmdDraw(
			p_cmd_buff.vk_cmd_buff,
			p_draw_info.vertex_count,
			p_draw_info.instance_count,
			p_draw_info.vertex_offset,
			p_draw_info.instance_offset,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_dispatch_indexed_draw_cmd :: #force_inline proc(
		p_draw_stream: ^DrawStream,
		p_cmd_buff: ^CommandBufferResource,
		p_draw_info: ^IndexedDrawInfo,
	) {
		vertex_buffer := get_buffer(p_draw_info.vertex_buffer_ref).vk_buffer
		vertex_buffer_offset := vk.DeviceSize(p_draw_info.vertex_buffer_offset)

		index_buffer := get_buffer(p_draw_info.index_buffer_ref).vk_buffer
		index_buffer_offset := vk.DeviceSize(p_draw_info.index_buffer_offset)

		vk.CmdBindVertexBuffers(
			p_cmd_buff.vk_cmd_buff,
			0,
			1,
			&vertex_buffer,
			&vertex_buffer_offset,
		)

		vk.CmdBindIndexBuffer(
			p_cmd_buff.vk_cmd_buff,
			index_buffer,
			index_buffer_offset,
			INDEX_TYPE_MAPPING[p_draw_info.index_type],
		)

		vk.CmdDrawIndexed(
			p_cmd_buff.vk_cmd_buff,
			p_draw_info.index_count,
			p_draw_info.instance_count,
			p_draw_info.index_offset,
			0,
			p_draw_info.instance_offset,
		)
	}

	//---------------------------------------------------------------------------//


	@(private)
	backend_draw_stream_change_pipeline :: #force_inline proc(
		p_draw_stream: ^DrawStream,
		p_cmd_buff: ^CommandBufferResource,
		p_pipeline: ^PipelineResource,
	) {
		vk.CmdBindPipeline(p_cmd_buff.vk_cmd_buff, .GRAPHICS, p_pipeline.vk_pipeline)
	}

	//---------------------------------------------------------------------------//
}

//---------------------------------------------------------------------------//
