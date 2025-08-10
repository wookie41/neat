package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INDEX_TYPE_MAPPING := []vk.IndexType{.UINT16, .UINT32}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_dispatch_bind_vertex_buffer :: #force_inline proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_vertex_buffer_ref: BufferRef,
		p_bind_point: u32,
		p_offset: u32,
	) {
		cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		vertex_buffer := &g_resources.backend_buffers[buffer_get_idx(p_vertex_buffer_ref)]
		vertex_buffer_offset := vk.DeviceSize(p_offset)

		vk.CmdBindVertexBuffers(
			cmd_buffer.vk_cmd_buff,
			p_bind_point,
			1,
			&vertex_buffer.vk_buffer,
			&vertex_buffer_offset,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_dispatch_bind_index_buffer :: #force_inline proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_index_buffer_ref: BufferRef,
		p_offset: u32,
		p_index_type: IndexType,
	) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		index_buffer := &g_resources.backend_buffers[buffer_get_idx(p_index_buffer_ref)]
		index_buffer_offset := vk.DeviceSize(p_offset)

		vk.CmdBindIndexBuffer(
			backend_cmd_buffer.vk_cmd_buff,
			index_buffer.vk_buffer,
			index_buffer_offset,
			INDEX_TYPE_MAPPING[u32(p_index_type)],
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_submit_indexed_draw :: #force_inline proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_index_count: u32,
		p_instance_count: u32,
		p_first_instance: u32,
		p_pipeline_ref: GraphicsPipelineRef,
		p_push_constant: []rawptr,
	) {
		pipeline_idx := get_graphics_pipeline_idx(p_pipeline_ref)
		pipeline := &g_resources.graphics_pipelines[pipeline_idx]
		backend_pipeline := &g_resources.backend_graphics_pipelines[pipeline_idx]
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		for push_constant, i in pipeline.desc.push_constants {

			stage_flags := vk.ShaderStageFlags{}

			if .Vertex in push_constant.shader_stages {
				stage_flags += {.VERTEX}
			}

			if .Pixel in push_constant.shader_stages {
				stage_flags += {.FRAGMENT}
			}

			vk.CmdPushConstants(
				backend_cmd_buffer.vk_cmd_buff,
				backend_pipeline.vk_pipeline_layout,
				stage_flags,
				push_constant.offset_in_bytes,
				push_constant.size_in_bytes,
				p_push_constant[i],
			)
		}

		vk.CmdDrawIndexed(
			backend_cmd_buffer.vk_cmd_buff,
			p_index_count,
			p_instance_count,
			0,
			0,
			p_first_instance,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_draw_stream_submit_draw :: #force_inline proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_vertex_count: u32,
		p_instance_count: u32,
	) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		vk.CmdDraw(backend_cmd_buffer.vk_cmd_buff, p_vertex_count, p_instance_count, 0, 0)
	}


	//---------------------------------------------------------------------------//
}

//---------------------------------------------------------------------------//
