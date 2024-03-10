package renderer

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private)
	backend_compute_command_dispatch :: proc(
		p_ref: ComputeCommandRef,
		p_cmd_buff_ref: CommandBufferRef,
		p_pipeline_ref: ComputePipelineRef,
		p_work_group_count: glsl.uvec3,
		p_push_constant: []rawptr,
	) {
		cmd_buff := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		pipeline_idx := get_compute_pipeline_idx(p_pipeline_ref)
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

		vk.CmdDispatch(
			cmd_buff.vk_cmd_buff,
			p_work_group_count.x,
			p_work_group_count.y,
			p_work_group_count.z,
		)
	}

	//---------------------------------------------------------------------------//

}
