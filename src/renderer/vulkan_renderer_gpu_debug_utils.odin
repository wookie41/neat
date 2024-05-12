package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:strings"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	backend_gpu_debug_region_begin :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_region: string,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		markerInfo := vk.DebugMarkerMarkerInfoEXT {
			sType       = .DEBUG_MARKER_MARKER_INFO_EXT,
			pMarkerName = strings.clone_to_cstring(p_region, temp_arena.allocator),
		}

		cmd_buff := g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		vk.CmdDebugMarkerBeginEXT(cmd_buff.vk_cmd_buff, &markerInfo)
	}

	//---------------------------------------------------------------------------//

	@(private)
    backend_gpu_debug_region_end :: proc(
		p_cmd_buff_ref: CommandBufferRef,
	) {

		cmd_buff := g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
        vk.CmdDebugMarkerEndEXT(cmd_buff.vk_cmd_buff)
	}

    //---------------------------------------------------------------------------//

	@(private)
	backend_gpu_debug_marker_add :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_marker: string,
	) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		markerInfo := vk.DebugMarkerMarkerInfoEXT  {
			sType       = .DEBUG_MARKER_MARKER_INFO_EXT,
			pMarkerName = strings.clone_to_cstring(p_marker, temp_arena.allocator),
		}

		cmd_buff := g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		vk.CmdDebugMarkerInsertEXT(cmd_buff.vk_cmd_buff, &markerInfo)
	}

    //---------------------------------------------------------------------------//

}

//---------------------------------------------------------------------------//
