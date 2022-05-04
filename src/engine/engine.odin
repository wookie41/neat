package engine

//---------------------------------------------------------------------------//

import sdl "vendor:sdl2"

import "core:log"
import "../renderer"

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

InitOptions :: struct {
	window_width, window_height: u32,
}

//---------------------------------------------------------------------------//

G_ENGINE : struct {
	window: ^sdl.Window,
}

//---------------------------------------------------------------------------//

@(private)
G_ENGINE_LOG: log.Logger

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
    
    G_ENGINE_LOG = log.create_console_logger()
    context.logger = G_ENGINE_LOG

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
		{.VULKAN},
	)

	if G_ENGINE.window == nil {
		return false
	}

	//Init renderer
	{
		renderer_init_options := renderer.InitOptions {
			allocator = context.allocator,
		}

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
        if sdl_event.type == .QUIT || 
            sdl_event.type == .KEYDOWN && sdl_event.key.keysym.scancode == .ESCAPE {
            running = false
        }

        renderer.update(0)
    }
}