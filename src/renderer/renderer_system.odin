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

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:        BackendRendererState,
	num_frames_in_flight:       u32,
	frame_idx:                  u32,
	primary_cmd_buffer_handles: []CommandBufferHandle,
	queued_image_copies:        [dynamic]BufferImageCopy,
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

MemoryAccessFlagBits :: enum u32 {
	/////////////////////////////////////////////////////////////////////////////
	// Read access
	VertexShaderSampledImageRead, // Read as a sampled image in a vertex shader
	FragmentShaderSampledImageRead, // Read as a sampled image in a fragment shader
	ComputeShaderSampledImageRead, // Read as a sampled image in a compute shader
	ColorAttachmentRead, // Read by standard blending/logic operations or subpass load operations
	DepthStencilAttachmentRead, // Read by depth/stencil tests or subpass load operations
	DepthStencilAttachmentReadOnly, // Read by depth/stencil tests or subpass load operations while also being bound as a sampled image
	// Read access - Buffers
	IndirectBufferRead, // Read as an indirect buffer for draw/dispatch
	IndexBufferRead, // Read as an index buffer for draw
	VertexBufferRead, // Read as a vertex buffer for draw
	VertexShaderUniformBufferRead, // Read as a uniform buffer in a vertex shader
	FragmentShaderUniformBufferRead, // Read as a uniform buffer in a fragment shader
	ComputeShaderUniformBufferRead, // Read as a uniform buffer in a compute shader
	// Read access - General
	VertexShaderGeneralRead, // Read as any resource in a vertex shader
	FragmentShaderGeneralRead, // Read as any resource in a fragment shader
	ComputeShaderGeneralRead, // Read as any resource in a compute shader
	TransferRead, // Read as the source of a transfer operation
	HostRead, // Read on the host
	// Write access - Images
	ColorAttachmentWrite, // Written as a color attachment in a draw, or via a subpass store op
	DepthStencilAttachmentWrite, // Written as a depth/stencil attachment during draw, or via a subpass store op
	// Write access - General
	ComputeShaderWrite, // Written as any resource in a compute shader
	AnyShaderWrite, // Written as any resource in any shader stage
	TransferWrite, // Written as the destination of a transfer operation
	HostWrite, // Written on the host
	/////////////////////////////////////////////////////////////////////////////
	WriteStart = ColorAttachmentWrite,
}

MemoryAccessFlags :: distinct bit_set[MemoryAccessFlagBits;u32]

//---------------------------------------------------------------------------//

ImageBarrierFlagBits :: enum u8 {
	Discard,
}

ImageBarrierFlags :: distinct bit_set[ImageBarrierFlagBits;u8]

//---------------------------------------------------------------------------//

ImageBarrier :: struct {
	image:       ImageRef,
	base_layer:  u8,
	layer_count: u8,
	base_mip:    u8,
	mip_count:   u8,
	access:      MemoryAccessFlags,
	flags:       ImageBarrierFlags,
	queue_idx:   u32,
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

	G_RENDERER.queued_image_copies = make(
		[dynamic]BufferImageCopy,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	setup_renderer_context()
	backend_init(p_options) or_return

	init_command_buffers(p_options) or_return

	// Allocate primary command buffer for each frame
	{
		G_RENDERER.primary_cmd_buffer_handles = make(
			[]CommandBufferHandle,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for i in 0 .. G_RENDERER.num_frames_in_flight {
			handle, succes := allocate_command_buffer(
				{flags = {.Primary}, thread = 0, frame = u8(i)},
			)
			if succes == false {
				log.error("Failed to allocate command buffer")
				return false
			}
			G_RENDERER.primary_cmd_buffer_handles[i] = handle
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
	execute_queued_image_copies()
	clear(&G_RENDERER.queued_image_copies)
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
get_frame_cmd_buffer_handle :: proc() -> CommandBufferHandle {
	return G_RENDERER.primary_cmd_buffer_handles[G_RENDERER.frame_idx]
}

//---------------------------------------------------------------------------//

@(private)
execute_queued_image_copies :: proc() {
	cmd_buff := get_frame_cmd_buffer_handle()
	cmd_copy_buffer_to_image(cmd_buff, G_RENDERER.queued_image_copies)
	clear(&G_RENDERER.queued_image_copies)
}


//---------------------------------------------------------------------------//
