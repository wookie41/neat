package renderer

//---------------------------------------------------------------------------//

import "core:mem"
import "core:log"

import "../common"

//---------------------------------------------------------------------------//


@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

@(private)
MAX_NUM_FRAMES_IN_FLIGHT :: #config(NUM_FRAMES_IN_FLIGHT, 2)

//---------------------------------------------------------------------------//

// @TODO Move to a config file

@(private)
MAX_SHADERS :: #config(MAX_SHADERS, 128)
MAX_PIPELINE_LAYOUTS :: #config(MAX_PIPELINE_LAYOUTS, 256)
MAX_IMAGES :: #config(MAX_IMAGES, 256)

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state: BackendRendererState,
}

@(private)
G_RENDERER_ALLOCATORS: struct {
	main_allocator:       mem.Allocator,
	resource_arena:       mem.Arena,
	resource_allocator:   mem.Allocator,
	temp_arena:           mem.Arena,
	temp_arena_allocator: mem.Allocator,
}

@(private)
G_RENDERER_LOG: log.Logger

//---------------------------------------------------------------------------//

InitOptions :: struct {
	using backend_options: BackendInitOptions,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
	G_RENDERER_LOG = log.create_console_logger()

	// Just take the current context allocator for now
	G_RENDERER_ALLOCATORS.main_allocator = context.allocator
	
	// Temp arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.temp_arena,
		make([]byte, common.MEGABYTE * 4, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.temp_arena_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.temp_arena,
	)

	// Resource arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.resource_arena,
		make([]byte, common.MEGABYTE * 4, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.resource_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.resource_arena,
	)

	setup_renderer_context()

	init_pipeline_layouts()
	init_images()

	backend_init(p_options) or_return
	load_shaders() or_return

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

setup_renderer_context :: proc() {
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_arena_allocator
	context.logger = G_RENDERER_LOG
}
//---------------------------------------------------------------------------//
