package renderer

//---------------------------------------------------------------------------//

import "../common"

//---------------------------------------------------------------------------//

@(private)
gpu_debug_region_begin :: proc {
	gpu_debug_region_begin_str,
	gpu_debug_region_begin_name,
}

//---------------------------------------------------------------------------//

@(private)
gpu_debug_marker_add :: proc {
	gpu_debug_marker_add_str,
	gpu_debug_marker_add_name,
}

//---------------------------------------------------------------------------//

@(private)
gpu_debug_region_end :: proc(p_cmd_buff_ref: CommandBufferRef) {
	if !G_RENDERER.debug_mode {
		return
	}
	backend_gpu_debug_region_end(p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//

@(private = "file")
gpu_debug_region_begin_name :: proc(p_cmd_buff_ref: CommandBufferRef, p_region: common.Name) {
	gpu_debug_region_begin_str(p_cmd_buff_ref, common.get_string(p_region))
}

//---------------------------------------------------------------------------//

@(private = "file")
gpu_debug_region_begin_str :: proc(p_cmd_buff_ref: CommandBufferRef, p_region: string) {
	if !G_RENDERER.debug_mode {
		return
	}
	backend_gpu_debug_region_begin(p_cmd_buff_ref, p_region)
}

//---------------------------------------------------------------------------//

@(private = "file")
gpu_debug_marker_add_name :: proc(p_cmd_buff_ref: CommandBufferRef, p_marker: common.Name) {
	gpu_debug_marker_add_str(p_cmd_buff_ref, common.get_string(p_marker))
}

//---------------------------------------------------------------------------//

@(private = "file")
gpu_debug_marker_add_str :: proc(p_cmd_buff_ref: CommandBufferRef, p_marker: string) {
	if !G_RENDERER.debug_mode {
		return
	}
	backend_gpu_debug_marker_add(p_cmd_buff_ref, p_marker)
}

//---------------------------------------------------------------------------//
