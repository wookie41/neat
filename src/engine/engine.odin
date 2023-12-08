package engine


//---------------------------------------------------------------------------//

import sdl "vendor:sdl2"

import "core:log"
import "core:math/linalg/glsl"
import "core:time"

import "../common"
import "../renderer"

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

InitOptions :: struct {
	window_width, window_height: u32,
}

//---------------------------------------------------------------------------//

G_ENGINE: struct {
	window: ^sdl.Window,
}

//---------------------------------------------------------------------------//

@(private)
G_ENGINE_LOG: log.Logger

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	last_frame_mouse_pos: glsl.ivec2,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {

	G_ENGINE_LOG = log.create_console_logger()
	context.logger = G_ENGINE_LOG

	mem_init(MemoryInitOptions{total_available_memory = 512 * common.MEGABYTE})

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

	sdl.GetMouseState(&INTERNAL.last_frame_mouse_pos.x, &INTERNAL.last_frame_mouse_pos.x)

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

	camera_init()

	INTERNAL.last_frame_mouse_pos = {0, 0}

	return true
}

//---------------------------------------------------------------------------//

run :: proc() {
	sdl_event: sdl.Event
	running := true

	last_frame_time := time.now()
	target_dt: f32 = 1.0 / 60.0

	for running {

		current_time := time.now()
		dt := f32(time.duration_seconds(time.diff(last_frame_time, current_time)))
		render_dt := dt

		mouse_pos: glsl.ivec2
		pressed_mouse_buttons := sdl.GetMouseState(&mouse_pos.x, &mouse_pos.y)

		active_keys := sdl.GetKeyboardState(nil)

		for sdl.PollEvent(&sdl_event) {
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
			case .MOUSEWHEEL:
				if sdl_event.wheel.y > 0 {
					camera_add_speed(1)
				} else if sdl_event.wheel.y < 0 {
					camera_add_speed(-1)
				}
			}

			renderer.process_sdl_event(&sdl_event)
		}

		if active_keys[sdl.SCANCODE_ESCAPE] > 0 {
			running = false
			continue
		}

		if active_keys[sdl.SCANCODE_W] > 0 {
			camera_add_forward_velocity(1)
		}
		if active_keys[sdl.SCANCODE_S] > 0 {
			camera_add_forward_velocity(-1)
		}
		if active_keys[sdl.SCANCODE_D] > 0 {
			camera_add_right_velocity(1)
		}
		if active_keys[sdl.SCANCODE_A] > 0 {
			camera_add_right_velocity(-1)
		}

		if (pressed_mouse_buttons & u32(sdl.BUTTON(3))) > 0 {
			x_delta := mouse_pos.x - INTERNAL.last_frame_mouse_pos.x
			y_delta := mouse_pos.y - INTERNAL.last_frame_mouse_pos.y
			camera_add_rotation(f32(x_delta), -f32(y_delta))
		}

		for dt > target_dt {
			camera_update(target_dt)
			dt -= target_dt
		}

		// Update renderer camera
		renderer.g_render_camera.position = Camera.position
		renderer.g_render_camera.forward = Camera.forward
		renderer.g_render_camera.up = Camera.up
		renderer.g_render_camera.fov_degrees = Camera.fov
		renderer.g_render_camera.near_plane = Camera.near_plane
		renderer.g_render_camera.far_plane = Camera.far_plane

		renderer.update(render_dt)

		INTERNAL.last_frame_mouse_pos = mouse_pos
	}
}
