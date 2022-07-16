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
MAX_PIPELINE_LAYOUTS :: #config(MAX_PIPELINE_LAYOUTS, 128)
MAX_IMAGES :: #config(MAX_IMAGES, 256)
MAX_BUFFERS :: #config(MAX_BUFFERS, 256)
MAX_RENDER_PASSES :: #config(MAX_RENDER_PASSES, 256)
MAX_PIPELINES :: #config(MAX_PIPELINES, 128)
MAX_COMMAND_BUFFERS :: #config(MAX_PIPELINES, 32)

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:          BackendRendererState,
	num_frames_in_flight:         u32,
	frame_idx:                    u32,
	primary_cmd_buffer_ref:       []CommandBufferRef,
	queued_textures_copies:       [dynamic]TextureCopy,
	current_frame_swap_image_idx: u32,
	swap_image_refs:              []ImageRef,
	depth_buffer_ref: ImageRef,
}

@(private)
G_RENDERER_ALLOCATORS: struct {
	main_allocator:     mem.Allocator,
	resource_arena:     mem.Arena,
	resource_allocator: mem.Allocator,
	temp_arena:         mem.Arena,
	temp_allocator:     mem.Allocator,
	frame_arena:        mem.Arena,
	frame_allocator:    mem.Allocator,
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
	G_RENDERER_ALLOCATORS.temp_allocator = mem.arena_allocator(
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

	// Frame arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.frame_arena,
		make([]byte, common.MEGABYTE * 4, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.frame_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.frame_arena,
	)

	G_RENDERER.queued_textures_copies = make(
		[dynamic]TextureCopy,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	setup_renderer_context()
	backend_init(p_options) or_return
	create_swap_images()

	init_command_buffers(p_options) or_return

	// Create depth buffer
	{
		dept_buffer_desc := ImageDesc {
			type = .OneDimensional,
			format = .Depth32SFloat,
			mip_count = 1,
			data_per_mip = nil,
			sample_count_flags = ._1,
		}


		G_RENDERER.depth_buffer_ref = create_image(depth_buffer_desc)
	}

	// Allocate primary command buffer for each frame
	{
		G_RENDERER.primary_cmd_buffer_ref = make(
			[]CommandBufferRef,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for i in 0 .. G_RENDERER.num_frames_in_flight {
			cmd_buff_ref := create_command_buffer(
				{flags = {.Primary}, thread = 0, frame = u8(i)},
			)
			if cmd_buff_ref != InvalidCommandBufferRef {
				log.error("Failed to allocate command buffer")
				return false
			}
			G_RENDERER.primary_cmd_buffer_ref[i] = cmd_buff_ref
			return true
		}
	}

	init_pipeline_layouts()
	init_buffers()
	init_images()

	load_shaders() or_return

	init_vt()
	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
	setup_renderer_context()
	// @TODO build command buffer
	execute_queued_texture_copies()
	clear(&G_RENDERER.queued_textures_copies)
	// @TODO dispatch command buffer
	backend_update(p_dt)
}

//---------------------------------------------------------------------------//

deinit :: proc() {
	setup_renderer_context()
	deinit_pipelines()
	deinit_backend()
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

@(private)
setup_renderer_context :: proc() {
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_allocator
	context.logger = G_RENDERER_LOG
}

//---------------------------------------------------------------------------//

@(private)
get_frame_cmd_buffer :: proc() -> CommandBufferRef {
	return G_RENDERER.primary_cmd_buffer_ref[G_RENDERER.frame_idx]
}

//---------------------------------------------------------------------------//

@(private)
execute_queued_texture_copies :: proc() {
	cmd_buff_ref := get_frame_cmd_buffer()
	backend_execute_queued_texture_copies(cmd_buff_ref)
}

//---------------------------------------------------------------------------//
