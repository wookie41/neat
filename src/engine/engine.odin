package engine

//---------------------------------------------------------------------------//

import sdl "vendor:sdl2"

import "core:log"
import "../renderer"
import "../common"

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

InitOptions :: struct {
	window_width, window_height: u32,
}

//---------------------------------------------------------------------------//

G_ENGINE: struct {
	window:           ^sdl.Window,
}

//---------------------------------------------------------------------------//

@(private)
G_ENGINE_LOG: log.Logger

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {

	G_ENGINE_LOG = log.create_console_logger()
	context.logger = G_ENGINE_LOG

	mem_init(MemoryInitOptions {
		total_available_memory = 512 * common.MEGABYTE,
	})

	common.init_names(G_ALLOCATORS.string_allocator)

	// Initialize assets
	texture_asset_init()
	material_asset_init()
	mesh_asset_init()

	// Initialize SDL2
	if sdl.Init(sdl.INIT_VIDEO) != 0 {
		return false
	}

	// Create window
	G_ENGINE.window = sdl.CreateWindow(
		"neat",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		i32(p_options.window_width),
		i32(p_options.window_height),
		{.VULKAN, .RESIZABLE},
	)

	if G_ENGINE.window == nil {
		return false
	}

	//Init renderer
	{
		renderer_init_options := renderer.InitOptions{}

		when USE_VULKAN_BACKEND {
			renderer_init_options.window = G_ENGINE.window
		}

		if renderer.init(renderer_init_options) == false {
			log.error("Failed to init renderer")
			return false
		}
	}

	return true
}

//---------------------------------------------------------------------------//

run :: proc() {
	sdl_event: sdl.Event
	running := true
	for running {
		sdl.PollEvent(&sdl_event)
		#partial switch sdl_event.type {
		case .QUIT:
			running = false
		case .WINDOWEVENT:
			if sdl_event.window.event == .RESIZED {
				renderer_event := renderer.WindowResizedEvent {
					windowID = sdl_event.window.windowID,
				}
				renderer.handler_on_window_resized(renderer_event)
			}
		case .KEYDOWN:
			if sdl_event.key.keysym.scancode == .ESCAPE {
				running = false
			}
		}
		renderer.update(0)
	}
}
