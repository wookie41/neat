package renderer

//---------------------------------------------------------------------------//

import "core:mem"
import "core:log"

import "../common"

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

@(private)
MAX_NUM_FRAMES_IN_FLIGHT :: #config(NUM_FRAMES_IN_FLIGHT, 2)

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:  BackendRendererState,
	allocator:            mem.Allocator,
	temp_arena:           mem.Arena,
	temp_arena_allocator: mem.Allocator,
}

@(private)
G_RENDERER_LOG: log.Logger

//---------------------------------------------------------------------------//

InitOptions :: struct {
	using backend_options: BackendInitOptions,
	allocator:             mem.Allocator,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
	G_RENDERER_LOG = log.create_console_logger()

	G_RENDERER.allocator = p_options.allocator
	mem.init_arena(
		&G_RENDERER.temp_arena,
		make([]byte, common.MEGABYTE * 4, p_options.allocator),
	)
	G_RENDERER.temp_arena_allocator = mem.arena_allocator(&G_RENDERER.temp_arena)

    setup_renderer_context()

	backend_init(p_options) or_return
	init_vt()
	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
    setup_renderer_context()
	backend_update(p_dt)
}

//---------------------------------------------------------------------------//

deinit :: proc() {
    setup_renderer_context()
	backend_deinit()
}

//---------------------------------------------------------------------------//

WindowResizedEvent :: struct {
	windowID: u32, //SDL2 window id
}

handler_on_window_resized :: proc(p_event: WindowResizedEvent) {
    setup_renderer_context()
    backend_handler_on_window_resized(p_event)
}

//---------------------------------------------------------------------------//

setup_renderer_context :: proc () {
    context.allocator = G_RENDERER.allocator
    context.temp_allocator = G_RENDERER.temp_arena_allocator
    context.logger = G_RENDERER_LOG
}
//---------------------------------------------------------------------------//
