package renderer

//---------------------------------------------------------------------------//

import "core:log"
import "core:mem"

import "../common"

//---------------------------------------------------------------------------//

BINDLESS_2D_IMAGES_COUNT :: 2048

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

@(private)
MAX_NUM_FRAMES_IN_FLIGHT :: #config(NUM_FRAMES_IN_FLIGHT, 2)

//---------------------------------------------------------------------------//

// @TODO Move to a config file

@(private)
MAX_TEST :: #config(MAX_TEST, 128)
MAX_SHADERS :: #config(MAX_SHADERS, 128)
MAX_IMAGES :: #config(MAX_IMAGES, 256)
MAX_BUFFERS :: #config(MAX_BUFFERS, 256)
MAX_RENDER_PASSES :: #config(MAX_RENDER_PASSES, 256)
MAX_RENDER_PASS_INSTANCES :: #config(MAX_RENDER_PASSES, 256)
MAX_PIPELINES :: #config(MAX_PIPELINES, 128)
MAX_COMMAND_BUFFERS :: #config(MAX_COMMAND_BUFFERS, 32)
MAX_BIND_GROUP_LAYOUTS :: #config(MAX_BIND_GROUP_LAYOUTS, 1024)
MAX_BIND_GROUPS :: #config(MAX_BIND_GROUPS, 1024)
MAX_RENDER_TASKS :: #config(MAX_RENDER_TASKS, 64)
MAX_MATERIAL_TYPES :: #config(MAX_MATERIAL_TYPES, 64)
MAX_MATERIAL_PASSES :: #config(MAX_MATERIAL_PASSES, 256)
MAX_MATERIAL_INSTANCES :: #config(MAX_MATERIAL_INSTANCES, 2048)
MAX_MESHES :: #config(MAX_MESHES, 1024)
MAX_MESH_INSTANCES :: #config(MAX_MESHES, 4096)

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	frame_id:  u32,
	frame_idx: u32, // frame_id % num_frames_in_flight 
}

//---------------------------------------------------------------------------//

g_resources: struct {
	images:                     #soa[]ImageResource,
	backend_images:             #soa[]BackendImageResource,
	buffers:                    #soa[]BufferResource,
	backend_buffers:            #soa[]BackendBufferResource,
	bind_group_layouts:         #soa[]BindGroupLayoutResource,
	bind_groups:                #soa[]BindGroupResource,
	backend_bind_groups:        #soa[]BackendBindGroupResource,
	backend_bind_group_layouts: #soa[]BackendBindGroupLayoutResource,
	cmd_buffers:                #soa[]CommandBufferResource,
	backend_cmd_buffers:        #soa[]BackendCommandBufferResource,
	pipelines:                  #soa[]PipelineResource,
	backend_pipelines:          #soa[]BackendPipelineResource,
	render_passes:              #soa[]RenderPassResource,
	backend_render_passes:      #soa[]BackendRenderPassResource,
}

//---------------------------------------------------------------------------//

GPUDeviceFlagsBits :: enum u8 {
	DedicatedTransferQueue,
	DedicatedComputeQueue,
	IntegratedGPU,
	SupportsReBAR,
}

GPUDeviceFlags :: distinct bit_set[GPUDeviceFlagsBits;u8]

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:                           BackendRendererState,
	num_frames_in_flight:                          u32,
	primary_cmd_buffer_ref:                        []CommandBufferRef,
	queued_textures_copies:                        [dynamic]TextureCopy,
	current_frame_swap_image_idx:                  u32,
	swap_image_refs:                               []ImageRef,
	swap_image_render_targets:                     []RenderTarget,
	gpu_device_flags:                              GPUDeviceFlags,
	global_bind_group_layout_ref:                  BindGroupLayoutRef,
	bindless_textures_array_bind_group_layout_ref: BindGroupLayoutRef,
	global_bind_group_ref:                         BindGroupRef,
	bindless_textures_array_bind_group_ref:        BindGroupRef,
}

@(private)
G_RENDERER_ALLOCATORS: struct {
	main_allocator:             mem.Allocator,
	// @TODO look for a better allocator here, but remember 
	// that we need free internal arrays of the resource
	temp_scratch_allocator:     mem.Scratch_Allocator,
	temp_allocator:             mem.Allocator,
	names_scratch_allocator:    mem.Scratch_Allocator,
	names_allocator:            mem.Allocator,
	resource_scratch_allocator: mem.Scratch_Allocator,
	resource_allocator:         mem.Allocator,
	frame_arena:                mem.Arena,
	frame_allocator:            mem.Allocator,

	// Stack used to sub-allocate scratch arenas from that are used within a function scope 
	temp_arenas_stack:          mem.Stack,
	temp_arenas_allocator:      mem.Allocator,
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

	// Temp allocator
	mem.scratch_allocator_init(
		&G_RENDERER_ALLOCATORS.temp_scratch_allocator,
		common.MEGABYTE * 8,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_RENDERER_ALLOCATORS.temp_allocator = mem.scratch_allocator(
		&G_RENDERER_ALLOCATORS.temp_scratch_allocator,
	)

	// Resource allocator
	mem.scratch_allocator_init(
		&G_RENDERER_ALLOCATORS.resource_scratch_allocator,
		common.MEGABYTE * 8,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_RENDERER_ALLOCATORS.resource_allocator = mem.scratch_allocator(
		&G_RENDERER_ALLOCATORS.resource_scratch_allocator,
	)

	// Frame allocator
	mem.arena_init(
		&G_RENDERER_ALLOCATORS.frame_arena,
		make([]byte, common.MEGABYTE * 8, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.frame_allocator = mem.arena_allocator(&G_RENDERER_ALLOCATORS.frame_arena)

	// Names allocator
	mem.scratch_allocator_init(
		&G_RENDERER_ALLOCATORS.names_scratch_allocator,
		common.MEGABYTE * 8,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_RENDERER_ALLOCATORS.names_allocator = mem.scratch_allocator(
		&G_RENDERER_ALLOCATORS.names_scratch_allocator,
	)

	G_RENDERER.queued_textures_copies = make(
		[dynamic]TextureCopy,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	INTERNAL.frame_idx = 0
	INTERNAL.frame_id = 0

	setup_renderer_context()
	backend_init(p_options) or_return

	init_shaders() or_return
	init_render_passes() or_return
	init_pipelines() or_return
	init_bind_group_layouts()
	init_bind_groups()
	init_buffers()
	init_meshes()
	init_images()
	init_command_buffers(p_options) or_return

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
			cmd_buffer := &g_resources.cmd_buffers[get_cmd_buffer_idx(cmd_buff_ref)]
			cmd_buffer.desc = {
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

	// Create the bind group for per frame/view data
	{
		// Bind group layout creation
		G_RENDERER.global_bind_group_layout_ref = allocate_bind_group_layout_ref(
			common.create_name("GlobalUniforms"),
			2, // per frame, per view
		)

		bind_group_layout_idx := get_bind_group_layout_idx(G_RENDERER.global_bind_group_layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		// Per frame uniform buffer
		bind_group_layout.desc.bindings[0] = BindGroupLayoutBinding {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .UniformBufferDynamic,
		}

		// Per view uniform buffer
		bind_group_layout.desc.bindings[1] = BindGroupLayoutBinding {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .UniformBufferDynamic,
		}

		if create_bind_group_layout(G_RENDERER.global_bind_group_layout_ref) == false {
			log.error("Failed to create the global uniforms bind group layout")
			return false
		}

		// Now create the bind group based on this layout
		G_RENDERER.global_bind_group_ref = allocate_bind_group_ref(
			common.create_name("GlobalUniforms"),
		)

		bind_group_idx := get_bind_group_idx(G_RENDERER.global_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		bind_group.desc.layout_ref = G_RENDERER.global_bind_group_layout_ref

		if create_bind_group(G_RENDERER.global_bind_group_ref) == false {
			log.error("Failed to create the global uniforms bind group")
			return false
		}
	}

	// Create the bind group layout for per bindless texture array data
	{
		// Layout
		G_RENDERER.bindless_textures_array_bind_group_layout_ref = allocate_bind_group_layout_ref(
			common.create_name("BindlessArray"),
			1 + len(SamplerType), // 2D texture array, sampled
		)

		bind_group_layout_idx := get_bind_group_layout_idx(
			G_RENDERER.bindless_textures_array_bind_group_layout_ref,
		)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		bind_group_layout.desc.flags = {.BindlessResources}

		// Samplers
		for i in 0 ..< len(SamplerType) {
			bind_group_layout.desc.bindings[i] = BindGroupLayoutBinding {
				count = 1,
				shader_stages = {.Vertex, .Fragment, .Compute},
				type = .Sampler,
			}
		}

		// 2D images array
		bind_group_layout.desc.bindings[len(SamplerType)] = BindGroupLayoutBinding {
			count = BINDLESS_2D_IMAGES_COUNT,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .Image,
			flags = {.BindlessImageArray},
		}

		if create_bind_group_layout(G_RENDERER.bindless_textures_array_bind_group_layout_ref) ==
		   false {
			log.error("Failed to create the bindless images bind group layout")
			return false
		}

		G_RENDERER.bindless_textures_array_bind_group_ref = allocate_bind_group_ref(
			common.create_name("BindlessArray"),
		)

		bind_group_idx := get_bind_group_idx(G_RENDERER.bindless_textures_array_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		bind_group.desc.layout_ref = G_RENDERER.bindless_textures_array_bind_group_layout_ref

		if create_bind_group(G_RENDERER.bindless_textures_array_bind_group_ref) == false {
			log.error("Failed to create the bindless images bind group")
			return false
		}
	}

	init_render_tasks() or_return
	init_material_passs() or_return
	init_material_types() or_return
	init_material_instances() or_return

	init_vt()

	setup_renderer_context()

	// Iterate over RenderTasks and call pre_render() for all of them
	// This is the initial frame, where everything inside the renderer 
	// is guaranteed to be created and so things like transfers can be requested 
	{
		cmd_buff := get_frame_cmd_buffer_ref()
		begin_command_buffer(cmd_buff)
		vt_create_texture_image()
		run_buffer_upload_requests()
		execute_queued_texture_copies()
		end_command_buffer(cmd_buff)
		submit_pre_render(cmd_buff)

		// Advance the frame index when using unified queues, as we don't want to wait for the 0th
		// command buffer to finish before we start recording the frame
		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			advance_frame_idx()
		}
	}

	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
	setup_renderer_context()


	// @TODO Render tasks - begin_frame()

	cmd_buff_ref := get_frame_cmd_buffer_ref()

	backend_wait_for_frame_resources()

	begin_command_buffer(cmd_buff_ref)

	buffer_upload_begin_frame()

	// @TODO Render tasks - render()

	backend_update(p_dt)

	execute_queued_texture_copies()
	run_buffer_upload_requests()
	batch_update_bindless_array_entries()

	end_command_buffer(cmd_buff_ref)

	submit_current_frame(cmd_buff_ref)

	// @TODO Render tasks - end_frame()

	// Recreate mesh queues
	{
		delete(g_created_mesh_refs)
		delete(g_destroyed_mesh_refs)

		g_created_mesh_refs = make([dynamic]MeshRef, G_RENDERER_ALLOCATORS.frame_allocator)

		for mesh_ref in g_destroyed_mesh_refs {
			free_mesh_ref(mesh_ref)
		}

		g_destroyed_mesh_refs = make([dynamic]MeshRef, G_RENDERER_ALLOCATORS.frame_allocator)
	}

	advance_frame_idx()

	assert(len(G_RENDERER_ALLOCATORS.temp_scratch_allocator.leaked_allocations) == 0)
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
advance_frame_idx :: #force_inline proc() {
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
	deinit_shaders()
	deinit_render_tasks()
	// @TODO deinit_bind_groups()
	// @TODO deinit_pipeline_layouts()
	// @TODOdeinit_pipelines()
	// @TODO deinit_images()
	// @TODO deinit_meshes()
	// @TODO deinit_buffers()
	// @TODO deinit_command_buffers(p_options)
	deinit_render_tasks()
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
get_frame_cmd_buffer_ref :: proc() -> CommandBufferRef {
	return G_RENDERER.primary_cmd_buffer_ref[get_frame_idx()]
}

//---------------------------------------------------------------------------//

@(private)
execute_queued_texture_copies :: proc() {
	cmd_buff_ref := get_frame_cmd_buffer_ref()
	if len(G_RENDERER.queued_textures_copies) > 0 {
		backend_execute_queued_texture_copies(cmd_buff_ref)
		clear(&G_RENDERER.queued_textures_copies)
	}
}

//---------------------------------------------------------------------------//
