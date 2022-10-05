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
MAX_RENDER_PASS_INSTANCES :: #config(MAX_RENDER_PASSES, 256)
MAX_PIPELINES :: #config(MAX_PIPELINES, 128)
MAX_COMMAND_BUFFERS :: #config(MAX_PIPELINES, 32)

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	frame_id:  u32,
	frame_idx: u32, // frame_id % num_frames_in_flight 
}

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:          BackendRendererState,
	num_frames_in_flight:         u32,
	primary_cmd_buffer_ref:       []CommandBufferRef,
	queued_textures_copies:       [dynamic]TextureCopy,
	current_frame_swap_image_idx: u32,
	swap_image_refs:              []ImageRef,
	swap_image_render_targets:    []RenderTarget,
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


@(private)
DeviceQueueType :: enum {
	Graphics,
	Compute,
	Transfer,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
	G_RENDERER_LOG = log.create_console_logger()

	// Just take the current context allocator for now
	G_RENDERER_ALLOCATORS.main_allocator = context.allocator

	// Temp arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.temp_arena,
		make([]byte, common.MEGABYTE * 8, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.temp_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.temp_arena,
	)

	// Resource arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.resource_arena,
		make([]byte, common.MEGABYTE * 8, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.resource_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.resource_arena,
	)

	// Frame arena
	mem.init_arena(
		&G_RENDERER_ALLOCATORS.frame_arena,
		make([]byte, common.MEGABYTE * 8, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.frame_allocator = mem.arena_allocator(
		&G_RENDERER_ALLOCATORS.frame_arena,
	)

	G_RENDERER.queued_textures_copies = make(
		[dynamic]TextureCopy,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	INTERNAL.frame_idx = 0
	INTERNAL.frame_id = 0

	setup_renderer_context()
	backend_init(p_options) or_return

	init_pipeline_layouts()
	init_pipelines()
	init_buffers()
	init_images()
	init_command_buffers(p_options) or_return

	load_shaders() or_return
	create_swap_images()

	{
		buffer_upload_options := BufferUploadInitOptions {
			staging_buffer_size = 64 * common.MEGABYTE,
			num_staging_regions = 2,
		}
		init_buffer_upload(buffer_upload_options) or_return
	}


	// Create RenderTargets for each swap image
	{
		G_RENDERER.swap_image_render_targets = make(
			[]RenderTarget,
			u32(len(G_RENDERER.swap_image_refs)),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for swap_image_ref, i in G_RENDERER.swap_image_refs {
			G_RENDERER.swap_image_render_targets[i] = RenderTarget {
				clear_value = {0, 0, 0, 1},
				current_usage = .Undefined,
				flags = {.Clear},
				image_mip = -1,
				image_ref = swap_image_ref,
			}
		}

	}

	// Allocate primary command buffer for each frame
	{
		G_RENDERER.primary_cmd_buffer_ref = make(
			[]CommandBufferRef,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for i in 0 ..< G_RENDERER.num_frames_in_flight {
			cmd_buff_ref := allocate_command_buffer_ref(common.create_name("CmdBuffer"))
			if cmd_buff_ref == InvalidCommandBufferRef {
				log.error("Failed to allocate command buffer")
				return false
			}
			get_command_buffer(cmd_buff_ref).desc = {
				flags = {.Primary},
				thread = 0,
				frame = u8(i),
			}
			if create_command_buffer(cmd_buff_ref) == false {
				log.error("Failed to create command buffer")
				return false
			}
			G_RENDERER.primary_cmd_buffer_ref[i] = cmd_buff_ref
		}
	}

	init_vt()

	setup_renderer_context()

	// Iterate over RenderTasks and call pre_render() for all of them
	// This is the initial frame, where everything inside the renderer 
	// is guaranteed to be created and so things like transfers can be requested 
	{
		cmd_buff := get_frame_cmd_buffer()
		begin_command_buffer(cmd_buff)
		vt_pre_render()
		run_buffer_upload_requests()
		execute_queued_texture_copies()
		end_command_buffer(cmd_buff)
		submit_pre_render(cmd_buff)

		// Advance the frame index when using unified queues, as we don't want to wait for the 0th
		// command buffer to finish before we start recording the frame
		if .DedicatedTransferQueue in G_RENDERER.device_hints {
			advance_frame_idx()
		}
	}

	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
	setup_renderer_context()

	clear(&G_RENDERER.queued_textures_copies)
	cmd_buff_ref := get_frame_cmd_buffer()

	backend_wait_for_frame_resources()

	begin_command_buffer(cmd_buff_ref)

	buffer_upload_begin_frame()

	backend_update(p_dt)

	execute_queued_texture_copies()
	run_buffer_upload_requests()

	end_command_buffer(cmd_buff_ref)

	submit_current_frame(cmd_buff_ref)

	advance_frame_idx()
}

//---------------------------------------------------------------------------//

get_frame_idx :: #force_inline proc() -> u32 {
	return INTERNAL.frame_idx
}

//---------------------------------------------------------------------------//

get_frame_id :: #force_inline proc() -> u32 {
	return INTERNAL.frame_id
}

//---------------------------------------------------------------------------//

@(private = "file")
advance_frame_idx :: proc() {
	INTERNAL.frame_id += 1
	INTERNAL.frame_idx = (INTERNAL.frame_idx + 1) % G_RENDERER.num_frames_in_flight
}

//---------------------------------------------------------------------------//

@(private)
submit_pre_render :: proc(p_cmd_buff_ref: CommandBufferRef) {
	backend_submit_pre_render(p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//

@(private)
submit_current_frame :: proc(p_cmd_buff_ref: CommandBufferRef) {
	backend_submit_current_frame(p_cmd_buff_ref)
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
	return G_RENDERER.primary_cmd_buffer_ref[get_frame_idx()]
}

//---------------------------------------------------------------------------//

@(private)
execute_queued_texture_copies :: proc() {
	cmd_buff_ref := get_frame_cmd_buffer()
	if len(G_RENDERER.queued_textures_copies) > 0 {
		backend_execute_queued_texture_copies(cmd_buff_ref)
	}
}

//---------------------------------------------------------------------------//
