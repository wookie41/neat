#+feature dynamic-literals

package renderer

//---------------------------------------------------------------------------//

import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"

import "../common"

import sdl "vendor:sdl2"
import imgui "../third_party/odin-imgui"

//---------------------------------------------------------------------------//

BINDLESS_2D_IMAGES_COUNT :: 2048

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

//---------------------------------------------------------------------------//

@(private)
MAX_NUM_FRAMES_IN_FLIGHT :: #config(NUM_FRAMES_IN_FLIGHT, 2)

//---------------------------------------------------------------------------//

// Helper enums where all types of global and bindless resources are listed
// Keep in sync with resources.hlsli
@(private)
GlobalResourceSlot :: enum {
	MeshInstanceInfosBuffer,
	MaterialsBuffer,
}

@(private)
BindlessResourceSlot :: enum {
	TextureArray2D,
}

//---------------------------------------------------------------------------//

// @TODO Move to a config file

@(private)
MAX_SHADERS :: #config(MAX_SHADERS, 128)
MAX_IMAGES :: #config(MAX_IMAGES, 256)
MAX_BUFFERS :: #config(MAX_BUFFERS, 256)
MAX_RENDER_PASSES :: #config(MAX_RENDER_PASSES, 128)
MAX_RENDER_PASS_INSTANCES :: #config(MAX_RENDER_PASSES, 128)
MAX_GRAPHICS_PIPELINES :: #config(MAX_GRAPHICS_PIPELINES, 128)
MAX_COMPUTE_PIPELINES :: #config(MAX_COMPUTE_PIPELINES, 128)
MAX_COMMAND_BUFFERS :: #config(MAX_COMMAND_BUFFERS, 32)
MAX_BIND_GROUP_LAYOUTS :: #config(MAX_BIND_GROUP_LAYOUTS, 32)
MAX_BIND_GROUPS :: #config(MAX_BIND_GROUPS, 256)
MAX_RENDER_TASKS :: #config(MAX_RENDER_TASKS, 64)
MAX_MATERIAL_TYPES :: #config(MAX_MATERIAL_TYPES, 64)
MAX_MATERIAL_PASSES :: #config(MAX_MATERIAL_PASSES, 256)
MAX_MATERIAL_INSTANCES :: #config(MAX_MATERIAL_INSTANCES, 2048)
MAX_MESHES :: #config(MAX_MESHES, 1024)
MAX_MESH_INSTANCES :: #config(MAX_MESHES, 4096)
MAX_COMPUTE_COMMANDS :: #config(MAX_COMPUTE_COMMANDS, 128)

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	frame_id:  u32,
	frame_idx: u32, // frame_id % num_frames_in_flight 
	logger:    log.Logger,
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
	graphics_pipelines:         #soa[]GraphicsPipelineResource,
	backend_graphics_pipelines: #soa[]BackendGraphicsPipelineResource,
	compute_pipelines:          #soa[]ComputePipelineResource,
	backend_compute_pipelines:  #soa[]BackendComputePipelineResource,
	render_passes:              #soa[]RenderPassResource,
	backrender_pass_endes:      #soa[]BackendRenderPassResource,
	render_tasks:               []RenderTaskResource,
	shaders:                    #soa[]ShaderResource,
	backend_shaders:            #soa[]BackendShaderResource,
	material_types:             #soa[]MaterialTypeResource,
	material_instances:         #soa[]MaterialInstanceResource,
	meshes:                     #soa[]MeshResource,
	mesh_instances:             #soa[]MeshInstanceResource,
	material_passes:            #soa[]MaterialPassResource,
	draw_commands:              #soa[]DrawCommandResource,
	compute_commands:           #soa[]ComputeCommandResource,
}

//---------------------------------------------------------------------------//

g_resource_refs: struct {
	graphics_pipelines: common.RefArray(GraphicsPipelineResource),
	compute_pipelines:  common.RefArray(ComputePipelineResource),
	shaders:            common.RefArray(ShaderResource),
	mesh_instances:     common.RefArray(MeshInstanceResource),
}

//---------------------------------------------------------------------------//


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
RendererConfig :: struct {
	render_resolution: glsl.uvec2,
}

//---------------------------------------------------------------------------//

@(private)
G_RENDERER: struct {
	using backend_state:            BackendRendererState,
	config:                         RendererConfig,
	num_frames_in_flight:           u32,
	primary_cmd_buffer_ref:         []CommandBufferRef,
	swap_image_refs:                []ImageRef,
	gpu_device_flags:               GPUDeviceFlags,
	uniforms_bind_group_layout_ref: BindGroupLayoutRef,
	globals_bind_group_layout_ref:  BindGroupLayoutRef,
	bindless_bind_group_layout_ref: BindGroupLayoutRef,
	uniforms_bind_group_ref:        BindGroupRef,
	globals_bind_group_ref:         BindGroupRef,
	bindless_bind_group_ref:        BindGroupRef,
	default_image_ref:              ImageRef,
	debug_mode:                     bool,
	min_uniform_buffer_alignment:   u32,
	blue_noise_image_ref:           ImageRef,
	volumetric_noise_image_ref:     ImageRef,
}

//---------------------------------------------------------------------------//

@(private)
G_RENDERER_ALLOCATORS: struct {
	main_allocator:        mem.Allocator,
	names_arena:           mem.Arena,
	names_allocator:       mem.Allocator,
	frame_arenas:          []mem.Arena,
	frame_allocators:      []mem.Allocator,
	resource_allocator:    mem.Allocator,
	// Stack used to sub-allocate scratch arenas from that are used within a function scope 
	temp_arenas_stack:     mem.Stack,
	temp_arenas_allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

@(private)
G_RENDERER_SETTINGS: struct {
	num_shadow_cascades:                      u32,
	debug_draw_shadow_cascades:               bool,
	fit_shadow_cascades:                      bool,
	stabilize_shadow_cascades:                bool,
	shadows_rendering_distance:               f32,
	directional_light_shadow_sampling_radius: f32,
}

InitOptions :: struct {
	using backend_options: BackendInitOptions,
}

//---------------------------------------------------------------------------//

@(private)
DeviceQueueType :: enum {
	Graphics,
	Compute,
	Transfer,
}

//---------------------------------------------------------------------------//

@(private = "file")
RenderTaskEntry :: struct {
	type:            string,
	name:            string,
	config:          map[string]string,
	material_passes: []string,
}

//---------------------------------------------------------------------------//

g_render_camera := RenderCamera{}
@(private)
g_previous_render_camera := RenderCamera{}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
	INTERNAL.logger = log.create_console_logger()

	// Just take the current context allocator for now
	G_RENDERER_ALLOCATORS.main_allocator = context.allocator

	// Resource allocator (temporary, have to use pool allocator here)
	G_RENDERER_ALLOCATORS.resource_allocator = G_RENDERER_ALLOCATORS.main_allocator

	// Frame allocators
	G_RENDERER_ALLOCATORS.frame_arenas = make([]mem.Arena, 2, G_RENDERER_ALLOCATORS.main_allocator)
	G_RENDERER_ALLOCATORS.frame_allocators = make(
		[]mem.Allocator,
		2,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	for i in 0 ..< 2 {
		mem.arena_init(
			&G_RENDERER_ALLOCATORS.frame_arenas[i],
			make([]byte, common.MEGABYTE * 16, G_RENDERER_ALLOCATORS.main_allocator),
		)
		G_RENDERER_ALLOCATORS.frame_allocators[i] = mem.arena_allocator(
			&G_RENDERER_ALLOCATORS.frame_arenas[i],
		)
	}

	// Names allocator
	mem.arena_init(
		&G_RENDERER_ALLOCATORS.names_arena,
		make([]byte, common.MEGABYTE * 8, G_RENDERER_ALLOCATORS.main_allocator),
	)
	G_RENDERER_ALLOCATORS.names_allocator = mem.arena_allocator(&G_RENDERER_ALLOCATORS.names_arena)


	INTERNAL.frame_idx = 0
	INTERNAL.frame_id = 0

	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.logger = INTERNAL.logger

	// Init renderer settings with default values
	G_RENDERER_SETTINGS.num_shadow_cascades = 3
	G_RENDERER_SETTINGS.directional_light_shadow_sampling_radius = 0.3
	G_RENDERER_SETTINGS.fit_shadow_cascades = true
	G_RENDERER_SETTINGS.stabilize_shadow_cascades = false
	G_RENDERER_SETTINGS.shadows_rendering_distance = 1500

	backend_init(p_options) or_return

	shader_init() or_return
	render_pass_init() or_return
	pipeline_init() or_return
	bind_group_layout_init()
	bind_group_init()
	buffer_init()
	mesh_init()
	image_init() or_return
	command_buffer_init(p_options) or_return
	buffer_management_init() or_return
	draw_command_init() or_return
	compute_command_init() or_return

	image_create_swap_images()

	{
		buffer_upload_options := BufferUploadInitOptions {
			staging_buffer_size       = 8 * common.MEGABYTE,
			staging_async_buffer_size = 8 * common.MEGABYTE,
		}
		buffer_upload_init(buffer_upload_options) or_return
	}

	// Init deferred resource deletion
	{
		using g_deferred_resource_delete_context

		per_frame_arenas = make(
			[]mem.Arena,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.main_allocator,
		)
		per_frame_allocators = make(
			[]mem.Allocator,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.main_allocator,
		)
		per_frame_deletes = make(
			[][dynamic]DeferredResourceDeleteEntry,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		for i in 0 ..< G_RENDERER.num_frames_in_flight {

			mem.arena_init(
				&per_frame_arenas[i],
				make([]byte, common.MEGABYTE * 4, G_RENDERER_ALLOCATORS.main_allocator),
			)
			per_frame_allocators[i] = mem.arena_allocator(&per_frame_arenas[i])
			per_frame_deletes[i] = make(
				[dynamic]DeferredResourceDeleteEntry,
				per_frame_allocators[i],
			)
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
			cmd_buff_ref := command_buffer_allocate(common.create_name("CmdBuffer"))
			if cmd_buff_ref == InvalidCommandBufferRef {
				log.error("Failed to allocate command buffer")
				return false
			}
			cmd_buffer := &g_resources.cmd_buffers[command_buffer_get_idx(cmd_buff_ref)]
			cmd_buffer.desc = {
				flags  = {.Primary},
				thread = 0,
				frame  = u8(i),
			}
			if command_buffer_create(cmd_buff_ref) == false {
				log.error("Failed to create command buffer")
				return false
			}
			G_RENDERER.primary_cmd_buffer_ref[i] = cmd_buff_ref
		}
	}

	// Create bind group layout for uniforms
	{
		// Bind group layout creation
		G_RENDERER.uniforms_bind_group_layout_ref = bind_group_layout_allocate(
			common.create_name("Uniforms"),
			2,
		)

		bind_group_layout_idx := bind_group_layout_get_idx(
			G_RENDERER.uniforms_bind_group_layout_ref,
		)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		// Per frame uniform buffer
		bind_group_layout.desc.bindings[0] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel, .Compute},
			type          = .UniformBufferDynamic,
		}

		// Per view uniform buffer
		bind_group_layout.desc.bindings[1] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel, .Compute},
			type          = .UniformBufferDynamic,
		}

		if bind_group_layout_create(G_RENDERER.uniforms_bind_group_layout_ref) == false {
			log.error("Failed to create the global uniforms bind group layout")
			return false
		}

		// Now create the bind group based on this layout
		G_RENDERER.uniforms_bind_group_ref = bind_group_allocate(common.create_name("Uniforms"))

		bind_group_idx := bind_group_get_idx(G_RENDERER.uniforms_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		bind_group.desc.layout_ref = G_RENDERER.uniforms_bind_group_layout_ref

		if bind_group_create(G_RENDERER.uniforms_bind_group_ref) == false {
			log.error("Failed to create the uniforms bind group")
			return false
		}
	}

	// Create the bind group layout for global resources
	{
		G_RENDERER.globals_bind_group_layout_ref = bind_group_layout_allocate(
			common.create_name("Globals"),
			len(GlobalResourceSlot),
		)

		bind_group_layout_idx := bind_group_layout_get_idx(
			G_RENDERER.globals_bind_group_layout_ref,
		)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		bind_group_layout.desc.bindings[GlobalResourceSlot.MeshInstanceInfosBuffer] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel, .Compute},
			type          = .StorageBuffer,
		}

		bind_group_layout.desc.bindings[GlobalResourceSlot.MaterialsBuffer] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel, .Compute},
			type          = .StorageBuffer,
		}

		if bind_group_layout_create(G_RENDERER.globals_bind_group_layout_ref) == false {
			log.error("Failed to create the bindless resources bind group layout")
			return false
		}

		G_RENDERER.globals_bind_group_ref = bind_group_allocate(common.create_name("Globals"))

		bind_group_idx := bind_group_get_idx(G_RENDERER.globals_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		bind_group.desc.layout_ref = G_RENDERER.globals_bind_group_layout_ref

		if bind_group_create(G_RENDERER.globals_bind_group_ref) == false {
			log.error("Failed to create the global resources bind group")
			return false
		}
	}

	// Create the bind group layout for bindless resources
	{
		G_RENDERER.bindless_bind_group_layout_ref = bind_group_layout_allocate(
			common.create_name("Bindless"),
			len(BindlessResourceSlot) + len(SamplerType),
		)

		bind_group_layout_idx := bind_group_layout_get_idx(
			G_RENDERER.bindless_bind_group_layout_ref,
		)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		// Give a hint to the backend that this bind group contains bindless resources
		// Some backends need it to configure the bind group differently, e.g. on Vulkan
		// we need to add the UPDATE_AFTER_BIND_POOL
		bind_group_layout.desc.flags = {.BindlessResources}

		bind_group_layout.desc.bindings[BindlessResourceSlot.TextureArray2D] =
			BindGroupLayoutBinding {
				count         = BINDLESS_2D_IMAGES_COUNT,
				shader_stages = {.Vertex, .Pixel, .Compute},
				type          = .Image,
				flags         = {.BindlessImageArray},
			}

		// Add all of the samplers to this bind group
		for i in 0 ..< len(SamplerType) {
			bind_group_layout.desc.bindings[len(BindlessResourceSlot) + i] =
				BindGroupLayoutBinding {
					count                 = 1,
					shader_stages         = {.Vertex, .Pixel, .Compute},
					type                  = .Sampler,
					immutable_sampler_idx = u32(i),
				}
		}

		if bind_group_layout_create(G_RENDERER.bindless_bind_group_layout_ref) == false {
			log.error("Failed to create the bindless resources bind group layout")
			return false
		}

		G_RENDERER.bindless_bind_group_ref = bind_group_allocate(common.create_name("Bindless"))

		bind_group_idx := bind_group_get_idx(G_RENDERER.bindless_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		bind_group.desc.layout_ref = G_RENDERER.bindless_bind_group_layout_ref

		if bind_group_create(G_RENDERER.bindless_bind_group_ref) == false {
			log.error("Failed to create the bindless group")
			return false
		}
	}


	render_task_init() or_return
	material_pass_init() or_return
	material_type_init() or_return
	material_instance_init() or_return
	mesh_instance_init() or_return

	uniform_buffer_init()
	init_jobs() or_return

	// Load global textures - blue noise etc.
	{
		G_RENDERER.blue_noise_image_ref = image_load_from_path(
			common.create_name("BlueNoise"),
			"app_data/renderer/assets/textures/LDR_RG01_0.png",
		)

		// Volumetric noise texture
		{
			volumetric_noise_image_ref := image_allocate(common.create_name("VolumetricNoise"))
			volumetric_noise_image := &g_resources.images[image_get_idx(volumetric_noise_image_ref)]

			volumetric_noise_image.desc.array_size = 1
			volumetric_noise_image.desc.dimensions = {64, 64, 64}
			volumetric_noise_image.desc.flags = {.Sampled, .Storage}
			volumetric_noise_image.desc.mip_count = 1
			volumetric_noise_image.desc.format = .R8UNorm
			volumetric_noise_image.desc.type = .ThreeDimensional

			image_create(volumetric_noise_image_ref) or_return

			G_RENDERER.volumetric_noise_image_ref = volumetric_noise_image_ref
		}
	}

	load_renderer_config()

	// Update the uniforms and bindless resources bind groups with appropriate resources
	{
		using g_renderer_buffers

		mesh_instance_info_buffer := &g_resources.buffers[buffer_get_idx(mesh_instance_info_buffer_ref)]

		bind_group_update(
			G_RENDERER.uniforms_bind_group_ref,
			BindGroupUpdate {
				buffers = {
					{
						binding = 0,
						buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref,
						size = size_of(g_per_frame_data),
					},
					{
						binding = 1,
						buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref,
						size = size_of(PerViewData),
					},
				},
			},
		)

		global_bind_group_update := BindGroupUpdate {
			buffers = {
				{
					binding = u32(GlobalResourceSlot.MeshInstanceInfosBuffer),
					buffer_ref = mesh_instance_info_buffer_ref,
					size = mesh_instance_info_buffer.desc.size,
				},
				{
					binding = u32(GlobalResourceSlot.MaterialsBuffer),
					buffer_ref = material_instances_buffer_ref,
					size = MATERIAL_PROPERTIES_BUFFER_SIZE,
				},
			},
		}

		bind_group_update(G_RENDERER.globals_bind_group_ref, global_bind_group_update)
	}

	g_render_camera.position = {0, 0, 0}
	g_render_camera.forward = {0, 0, -1}
	g_render_camera.up = {0, 1, 0}
	g_render_camera.near_plane = 0.01
	g_render_camera.far_plane = 10000
	g_render_camera.fov = 45.0

	ui_init() or_return

	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.logger = INTERNAL.logger

	common.arena_reset_all()
	backend_wait_for_frame_resources()

	process_deferred_resource_deletes()

	shader_update()

	cmd_buff_ref := get_frame_cmd_buffer_ref()
	command_buffer_begin(cmd_buff_ref)

	if get_frame_id() == 0 {
		run_initial_frame_tasks()
	}

	backend_begin_frame()
	ui_begin_frame()

	buffer_upload_finalize_finished_uploads()
	image_finalize_finished_uploads()

	image_upload_begin_frame()
	buffer_upload_begin_frame()

	buffer_upload_run_last_frame_requests()
	image_update_bindless_array()
	buffer_upload_process_async_requests()
	image_progress_uploads()

	material_instance_update_dirty_materials()
	mesh_instance_send_transform_data()

	// Skip this on first frame, as initial resources are being loaded
	if get_frame_id() > 0 {
		render_task_update(p_dt)
		draw_debug_ui(p_dt)
	}

	ui_submit()

	backend_post_render()

	command_buffer_end(cmd_buff_ref)

	submit_current_frame()
	free_all(get_frame_allocator())

	advance_frame_idx()

	g_previous_render_camera = g_render_camera
}

//---------------------------------------------------------------------------//

run_initial_frame_tasks :: proc() {
	cmd_buff_ref := get_frame_cmd_buffer_ref()

	// Generate volumetric noise texture
	{
		volumetric_noise_image := &g_resources.images[image_get_idx(G_RENDERER.volumetric_noise_image_ref)]

		bindings := []Binding {
			OutputImageBinding{image_ref = G_RENDERER.volumetric_noise_image_ref, mip_count = 1},
		}

		generate_volumetric_noise_job, _ := generic_compute_job_create(
			common.create_name("GenerateVolumetricNoise"),
			shader_find_by_name("generate_volumetric_noise.comp"),
			bindings,
		)
		defer generic_compute_job_destroy(generate_volumetric_noise_job)

		transition_binding_resources(bindings, .Compute)

		compute_command_dispatch(
			generate_volumetric_noise_job.compute_command_ref,
			cmd_buff_ref,
			{
				volumetric_noise_image.desc.dimensions.x / 8,
				volumetric_noise_image.desc.dimensions.y / 8,
				volumetric_noise_image.desc.dimensions.z,
			},
			{nil, {0, 0}, nil, nil},
		)
	}
}

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
	INTERNAL.frame_idx = INTERNAL.frame_id % G_RENDERER.num_frames_in_flight
}

//---------------------------------------------------------------------------//

@(private)
submit_current_frame :: proc() {
	buffer_upload_submit_pre_graphics()
	backend_submit_current_frame()
	buffer_upload_submit_post_graphics()
}

//---------------------------------------------------------------------------//

deinit :: proc() {
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.logger = INTERNAL.logger

	ui_shutdown()

	pipeline_deinit()
	shader_deinit()
	render_task_deinit()
	// @TODO deinit_bind_groups()
	// @TODO deinit_pipeline_layouts()
	// @TODOdeinit_pipelines()
	// @TODO deimage_init()
	// @TODO mesh_deinit()
	// @TODO debuffer_init()
	// @TODO decommand_buffer_init(p_options)
	render_task_deinit()
	deinit_backend()
}

//---------------------------------------------------------------------------//

WindowResizedEvent :: struct {
	windowID: u32, //SDL2 window id
}

handler_on_window_resized :: proc(p_event: WindowResizedEvent) {
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.logger = INTERNAL.logger

	backend_handler_on_window_resized(p_event)
}

//---------------------------------------------------------------------------//

@(private)
get_frame_cmd_buffer_ref :: proc() -> CommandBufferRef {
	return G_RENDERER.primary_cmd_buffer_ref[get_frame_idx()]
}

//---------------------------------------------------------------------------//

@(private = "file")
load_renderer_config :: proc() -> bool {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE) // The parser is quite memory hungry
	defer common.arena_delete(temp_arena)

	doc, err := xml.load_from_file(
		"app_data/renderer/config/renderer.xml",
		allocator = temp_arena.allocator,
	)
	if err != nil {
		log.fatal("Failed to load renderer config: %s\n", err)
		return false
	}

	render_width, render_width_found := common.xml_get_u32_attribute(doc, 0, "renderWidth")
	render_height, render_height_found := common.xml_get_u32_attribute(doc, 0, "renderHeight")

	if render_width_found == false || render_height_found == false {
		log.error("Render width or height not found\n")
		return false
	}

	G_RENDERER.config.render_resolution.x = render_width
	G_RENDERER.config.render_resolution.y = render_height

	renderer_config_image_creates(doc)
	renderer_config_load_render_tasks(doc)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
renderer_config_image_creates :: proc(p_doc: ^xml.Document) -> bool {
	images_id, images_found := xml.find_child_by_ident(p_doc, 0, "Images")
	if images_found == false {
		return true
	}

	images_element_ids := p_doc.elements[images_id]
	for image_element_id in images_element_ids.value {
		switch element_id in image_element_id {
		case string:
			continue
		case xml.Element_ID:
			child := p_doc.elements[element_id]

			if child.kind != .Element {continue} 	// Skip comments

			image_name := common.create_name(child.ident)

			image_format_name, format_found := xml.find_attribute_val_by_key(
				p_doc,
				element_id,
				"format",
			)
			if format_found == false {
				log.errorf("Failed to create image '%s' - no format specified\n", child.ident)
				continue
			}

			if (image_format_name in G_IMAGE_FORMAT_NAME_MAPPING) == false {
				log.errorf(
					"Failed to create image '%s' - unsupported format %s\n",
					child.ident,
					image_format_name,
				)
				continue
			}

			image_resolution_name, resolution_found := xml.find_attribute_val_by_key(
				p_doc,
				element_id,
				"resolution",
			)

			image_dimensions := glsl.uvec3{0, 0, 1}
			image_type := ImageType.OneDimensional

			if resolution_found {
				#partial switch G_RESOLUTION_NAME_MAPPING[image_resolution_name] {
				case .Full:
					image_dimensions.x = G_RENDERER.config.render_resolution.x
					image_dimensions.y = G_RENDERER.config.render_resolution.y
				case .Half:
					image_dimensions.x = G_RENDERER.config.render_resolution.x / 2
					image_dimensions.y = G_RENDERER.config.render_resolution.y / 2
				case .Quarter:
					image_dimensions.x = G_RENDERER.config.render_resolution.x / 4
					image_dimensions.y = G_RENDERER.config.render_resolution.y / 4
				case:
					assert(false, "unsupported res")
				}
				image_type = .TwoDimensional
			} else {

				width, width_found := common.xml_get_u32_attribute(p_doc, element_id, "width")
				height, height_found := common.xml_get_u32_attribute(p_doc, element_id, "height")
				depth, depth_found := common.xml_get_u32_attribute(p_doc, element_id, "depth")

				if width_found == false && height_found == false {
					log.errorf(
						"Failed to create image '%s' - couldn't determine dimensions",
						child.ident,
						image_format_name,
					)
					continue
				}

				if width_found {
					image_dimensions.x = width
				}

				if height_found {
					image_dimensions.y = height
					image_type = .TwoDimensional
				}

				if depth_found {
					image_dimensions.z = depth
					image_type = .ThreeDimensional
				}
			}

			_, is_storage_image := xml.find_attribute_val_by_key(p_doc, element_id, "storage")
			_, is_sampled_image := xml.find_attribute_val_by_key(p_doc, element_id, "sampled")

			image_flags := ImageDescFlags{}
			if is_storage_image {
				image_flags += {.Storage}
			}
			if is_sampled_image {
				image_flags += {.Sampled}
			}

			image_ref := image_allocate(image_name)
			image_idx := image_get_idx(image_ref)
			image := &g_resources.images[image_idx]

			image.desc.dimensions = image_dimensions
			image.desc.flags = image_flags
			image.desc.type = image_type
			image.desc.format = G_IMAGE_FORMAT_NAME_MAPPING[image_format_name]
			image.desc.mip_count, _ = common.xml_get_u32_attribute(
				p_doc,
				element_id,
				"mip_count",
				1,
			)
			image.desc.array_size, _ = common.xml_get_u32_attribute(
				p_doc,
				element_id,
				"array_size",
				1,
			)

			if image_create(image_ref) == false {
				log.errorf("Failed to create image '%s'\n", child.ident)
				continue
			}

			log.infof("Image '%s' created\n", child.ident)
		}
	}

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
renderer_config_load_render_tasks :: proc(p_doc: ^xml.Document) -> bool {
	render_tasks_id, render_tasks_found := xml.find_child_by_ident(p_doc, 0, "RenderTasks")
	if render_tasks_found == false {
		log.fatal("No render tasks defined in the renderer config\n")
		return false
	}

	render_tasks := p_doc.elements[render_tasks_id]
	for render_task_id in render_tasks.value {
		switch element_id in render_task_id {
		case string:
			continue
		case xml.Element_ID:
			child := p_doc.elements[element_id]

			if child.kind != .Element {continue} 	// Skip comments

			render_task_type, found := render_task_map_name_to_type(child.ident)
			if found == false {
				log.infof("Unsupported render task: %s\n", child.ident)
				continue
			}

			render_task_name, name_found := xml.find_attribute_val_by_key(
				p_doc,
				element_id,
				"name",
			)
			if name_found == false {
				log.errorf("Render task '%s' has no name specified\n", child.ident)
				continue
			}

			render_task_ref := render_task_allocate(common.create_name(render_task_name))
			g_resources.render_tasks[render_task_get_idx(render_task_ref)].desc.type =
				render_task_type


			render_task_config := RenderTaskConfig {
				doc                    = p_doc,
				render_task_element_id = element_id,
			}
			if render_task_create(render_task_ref, &render_task_config) == false {
				log.errorf("Failed to create render task '%s:%s'\n", child.ident, render_task_name)
				render_task_destroy(render_task_ref)
				continue
			}

			log.infof("Render task '%s:%s' created\n", child.ident, render_task_name)
		}
	}

	return true
}

//---------------------------------------------------------------------------//

process_sdl_event :: proc(p_sdl_event: ^sdl.Event) {
	ui_process_event(p_sdl_event)
}

//---------------------------------------------------------------------------//

@(private)
get_frame_allocator :: proc() -> mem.Allocator {
	return G_RENDERER_ALLOCATORS.frame_allocators[get_frame_id() % 2]
}


//---------------------------------------------------------------------------//

@(private)
get_next_frame_allocator :: proc() -> mem.Allocator {
	return G_RENDERER_ALLOCATORS.frame_allocators[(get_frame_id() + 1) % 2]
}

//---------------------------------------------------------------------------//

@(private)
resolve_resolution :: #force_inline proc(p_resolution: Resolution) -> glsl.uvec2 {
	switch p_resolution {
	case .Display:
		return glsl.uvec2{G_RENDERER.swap_extent.width, G_RENDERER.swap_extent.height}
	case .Full:
		return glsl.uvec2(G_RENDERER.config.render_resolution)
	case .Half:
		return glsl.uvec2(G_RENDERER.config.render_resolution) / 2
	case .Quarter:
		return glsl.uvec2(G_RENDERER.config.render_resolution) / 4
	}
	return glsl.uvec2(G_RENDERER.config.render_resolution)
}

//---------------------------------------------------------------------------//

@(private = "file")
init_jobs :: proc() -> bool {
	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_debug_ui :: proc(p_dt: f32) {

	imgui.SliderFloat3("Sun direction", &g_per_frame_data.sun.direction, -1, 1)
	imgui.SliderFloat("Sun strength", &g_per_frame_data.sun.strength, 0, 128000)

	// Debug UI
	render_task_draw_debug_ui()
}

//---------------------------------------------------------------------------//

@(private = "file")
DeferredResourceDeleteEntry :: struct {
	delete_func: proc(p_user_data: rawptr),
	user_data:   rawptr,
}

@(private = "file")
g_deferred_resource_delete_context: struct {
	per_frame_allocators: []mem.Allocator,
	per_frame_arenas:     []mem.Arena,
	per_frame_deletes:    [][dynamic]DeferredResourceDeleteEntry,
}

@(private)
defer_resource_delete :: proc(p_delete_func: proc(p_user_data: rawptr), $T: typeid) -> ^T {

	using g_deferred_resource_delete_context

	frame_idx := get_frame_idx()

	user_data := new(T, per_frame_allocators[frame_idx])
	new_entry := DeferredResourceDeleteEntry {
		delete_func = p_delete_func,
		user_data   = user_data,
	}
	append(&per_frame_deletes[frame_idx], new_entry)

	return user_data
}

@(private = "file")
process_deferred_resource_deletes :: proc() {

	using g_deferred_resource_delete_context

	frame_idx := get_frame_idx()

	for entry in &per_frame_deletes[frame_idx] {
		entry.delete_func(entry.user_data)
	}

	free_all(per_frame_allocators[frame_idx])
	per_frame_deletes[frame_idx] = make(
		[dynamic]DeferredResourceDeleteEntry,
		per_frame_allocators[frame_idx],
	)
}

//---------------------------------------------------------------------------//

@(private)
is_async_transfer_enabled :: #force_inline proc() -> bool {
	// Async transfer is disabled on first frame due to loading internal renderer textures
	return (.DedicatedTransferQueue in G_RENDERER.gpu_device_flags) && get_frame_id() > 0
}

//---------------------------------------------------------------------------//
