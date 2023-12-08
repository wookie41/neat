package renderer

//---------------------------------------------------------------------------//

import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"

import "../common"

import sdl "vendor:sdl2"

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
	pipelines:                  #soa[]PipelineResource,
	backend_pipelines:          #soa[]BackendPipelineResource,
	render_passes:              #soa[]RenderPassResource,
	backend_render_passes:      #soa[]BackendRenderPassResource,
	render_tasks:               []RenderTaskResource,
	shaders:                    #soa[]ShaderResource,
	backend_shaders:            #soa[]BackendShaderResource,
	material_types:             #soa[]MaterialTypeResource,
	material_instances:         #soa[]MaterialInstanceResource,
	meshes:                     #soa[]MeshResource,
	mesh_instances:             #soa[]MeshInstanceResource,
	material_passes:            #soa[]MaterialPassResource,
}
//---------------------------------------------------------------------------//

g_resource_refs: struct {
	mesh_instances: common.RefArray(MeshInstanceResource),
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
RendererConfig :: struct {
	render_size: glsl.uvec2,
}

//---------------------------------------------------------------------------//


@(private)
G_RENDERER: struct {
	using backend_state:                           BackendRendererState,
	config:                                        RendererConfig,
	num_frames_in_flight:                          u32,
	primary_cmd_buffer_ref:                        []CommandBufferRef,
	queued_textures_copies:                        [dynamic]TextureCopy,
	swap_image_refs:                               []ImageRef,
	gpu_device_flags:                              GPUDeviceFlags,
	global_bind_group_layout_ref:                  BindGroupLayoutRef,
	bindless_textures_array_bind_group_layout_ref: BindGroupLayoutRef,
	global_bind_group_ref:                         BindGroupRef,
	bindless_textures_array_bind_group_ref:        BindGroupRef,
}

//---------------------------------------------------------------------------//

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

//---------------------------------------------------------------------------//

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

g_render_camera: struct {
	position:    glsl.vec3,
	forward:     glsl.vec3,
	up:          glsl.vec3,
	fov_degrees: f32,
	near_plane:  f32,
	far_plane:   f32,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
	INTERNAL.logger = log.create_console_logger()

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

	INTERNAL.frame_idx = 0
	INTERNAL.frame_id = 0

	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_allocator
	context.logger = INTERNAL.logger

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
	buffer_management_init() or_return

	create_swap_images()

	{
		buffer_upload_options := BufferUploadInitOptions {
			staging_buffer_size = 16 * common.MEGABYTE,
			num_staging_regions = G_RENDERER.num_frames_in_flight,
		}
		init_buffer_upload(buffer_upload_options) or_return
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

	// Create the global bind group
	{
		// Bind group layout creation
		G_RENDERER.global_bind_group_layout_ref = allocate_bind_group_layout_ref(
			common.create_name("GlobalBuffer"),
			4, // per frame, per view, mesh instance buffer, material buffer
		)

		bind_group_layout_idx := get_bind_group_layout_idx(G_RENDERER.global_bind_group_layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		// Per frame uniform buffer
		bind_group_layout.desc.bindings[0] = {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .UniformBufferDynamic,
		}

		// Per view uniform buffer
		bind_group_layout.desc.bindings[1] =  {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .UniformBufferDynamic,
		}

		// Mesh instance info buffer
		bind_group_layout.desc.bindings[2] =  {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .StorageBuffer,
		}

		// Global materials buffer
		bind_group_layout.desc.bindings[3] = {
			count = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type = .StorageBuffer,
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
	init_mesh_instances() or_return

	load_renderer_config()
	uniform_buffer_management_init()

	// All of the global resources (sampler array and uniform buffers) have been created
	// So now we can update the global bind group
	{
		using g_renderer_buffers

		mesh_instance_info_buffer := &g_resources.buffers[get_buffer_idx(mesh_instance_info_buffer_ref)]

		bind_group_update(
			G_RENDERER.global_bind_group_ref,
			BindGroupUpdate{
				buffers = {
					{buffer_ref = InvalidBufferRef, size = 0},
					{
						buffer_ref = g_uniform_buffers.per_view_buffer_ref,
						size = size_of(g_per_view_uniform_buffer_data),
					},
					{
						buffer_ref = mesh_instance_info_buffer_ref,
						size = mesh_instance_info_buffer.desc.size,
					},
					{
						buffer_ref = material_instances_buffer_ref,
						size = MATERIAL_INSTANCES_BUFFER_SIZE,
					},
				},
			},
		)

	}


	g_render_camera.position = {0, 0, 0}
	g_render_camera.forward = {0, 0, -1}
	g_render_camera.up = {0, 1, 0}
	g_render_camera.near_plane = 0.1
	g_render_camera.far_plane = 10000
	g_render_camera.fov_degrees = 45.0

	ui_init() or_return

	return true
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_allocator
	context.logger = INTERNAL.logger

	cmd_buff_ref := get_frame_cmd_buffer_ref()

	backend_wait_for_frame_resources()

	begin_command_buffer(cmd_buff_ref)

	ui_begin_frame()

	buffer_upload_start_async_cmd_buffer()
	execute_queued_texture_copies()
	run_buffer_upload_requests()
	backend_buffer_upload_submit_async_transfers()

	batch_update_bindless_array_entries()

	free_all(G_RENDERER_ALLOCATORS.frame_allocator)

	buffer_upload_begin_frame()
	image_upload_begin_frame()
	material_instance_update_dirty_materials()
	mesh_instance_send_transform_data()

	uniform_buffer_management_update(p_dt)

	backend_update(p_dt)

	render_tasks_update(p_dt)

	backend_post_render()

	buffer_upload_pre_frame_submit()

	ui_submit()

	end_command_buffer(cmd_buff_ref)

	submit_current_frame()

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
advance_frame_idx :: proc() {
	INTERNAL.frame_id += 1
	INTERNAL.frame_idx = (INTERNAL.frame_idx + 1) % G_RENDERER.num_frames_in_flight
}

//---------------------------------------------------------------------------//

@(private)
submit_current_frame :: proc() {
	backend_submit_current_frame()
}

//---------------------------------------------------------------------------//

deinit :: proc() {
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_allocator
	context.logger = INTERNAL.logger

	ui_shutdown()

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
	// Setup renderer context
	context.allocator = G_RENDERER_ALLOCATORS.main_allocator
	context.temp_allocator = G_RENDERER_ALLOCATORS.temp_allocator
	context.logger = INTERNAL.logger

	backend_handler_on_window_resized(p_event)
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
	}
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

	G_RENDERER.config.render_size.x = render_width
	G_RENDERER.config.render_size.y = render_height

	renderer_config_create_images(doc)
	renderer_config_load_render_tasks(doc)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
renderer_config_create_images :: proc(p_doc: ^xml.Document) -> bool {
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
				switch G_RESOLUTION_NAME_MAPPING[image_resolution_name] {
				case .Full:
					image_dimensions.x = G_RENDERER.config.render_size.x
					image_dimensions.y = G_RENDERER.config.render_size.y
				case .Half:
					image_dimensions.x = G_RENDERER.config.render_size.x / 2
					image_dimensions.y = G_RENDERER.config.render_size.y / 2
				case .Quarter:
					image_dimensions.x = G_RENDERER.config.render_size.x / 4
					image_dimensions.y = G_RENDERER.config.render_size.y / 4
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

			image_ref := allocate_image_ref(image_name)
			image_idx := get_image_idx(image_ref)
			image := &g_resources.images[image_idx]

			image.desc.dimensions = image_dimensions
			image.desc.flags = image_flags
			image.desc.type = image_type
			image.desc.format = G_IMAGE_FORMAT_NAME_MAPPING[image_format_name]

			if create_image(image_ref) == false {
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

			render_task_ref := allocate_render_task_ref(common.create_name(render_task_name))
			g_resources.render_tasks[get_render_task_idx(render_task_ref)].desc.type =
				render_task_type


			render_task_config := RenderTaskConfig {
				doc                    = p_doc,
				render_task_element_id = element_id,
			}
			if create_render_task(render_task_ref, &render_task_config) == false {
				log.errorf("Failed to create render task '%s:%s'\n", child.ident, render_task_name)
				destroy_render_task(render_task_ref)
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
