package renderer

//---------------------------------------------------------------------------//

// This task prepares the cascades shadows - matrix, split etc
// based on the depth buffer. The cascades are tightly fitted to the depth buffer 
// to maximize precision. It's achived by calculating the min and max depth values
// during HiZ construction and then using it in this task to create the matrices.

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

@(private = "file")
CASCADE_SPLIT_LOG_FACTOR :: 0.90

@(private = "file")
FLAG_FIT_CASCADES :: 0x01

@(private = "file")
FLAG_STABILIZE_CASCADES :: 0x02

//---------------------------------------------------------------------------//

@(private = "file")
PrepareShadowCascadesRenderTaskData :: struct {
	compute_job:                GenericComputeJob,
	shadow_cascades_buffer_ref: BufferRef,
	min_max_depth_buffer_ref:   BufferRef,
	shadow_map_size:            f32,
	bindings:                   []Binding,
}

//---------------------------------------------------------------------------//

@(private = "file")
PrepareShadowCascadesUniformData :: struct #packed {
	num_cascades:               u32,
	split_factor:               f32,
	aspect_ratio:               f32,
	tan_fov_half:               f32,
	shadow_sampling_radius:     f32,
	flags:                      u32,
	shadows_rendering_distance: f32,
	shadow_map_size:            f32,
}

//---------------------------------------------------------------------------//

build_prepare_shadow_cascades_render_task_init :: proc(
	p_render_task_functions: ^RenderTaskFunctions,
) {
	p_render_task_functions.create_instance = create_instance
	p_render_task_functions.destroy_instance = destroy_instance
	p_render_task_functions.begin_frame = begin_frame
	p_render_task_functions.end_frame = end_frame
	p_render_task_functions.render = render
}

//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {
	doc_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"name",
	) or_return

	shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"shader",
	) or_return

	shadow_map_size := common.xml_get_f32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"shadowMapSize",
	) or_return


	shadow_cascades_buffer_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"shadowCascadesBuffer",
	) or_return

	shader_ref := shader_find_by_name(shader_name)
	if shader_ref == InvalidShaderRef {
		log.errorf(
			"Failed to create render task '%s' - invalid shader %s\n",
			doc_name,
			shader_name,
		)
		return false
	}

	// Create the shadow cascades buffer
	shadow_cascades_buffer_ref := buffer_allocate(common.create_name(shadow_cascades_buffer_name))
	shadow_cascades_buffer := &g_resources.buffers[buffer_get_idx(shadow_cascades_buffer_ref)]
	shadow_cascades_buffer.desc.flags = {.Dedicated}
	shadow_cascades_buffer.desc.size = size_of(ShadowCascade) * MAX_SHADOW_CASCADES
	shadow_cascades_buffer.desc.usage = {.StorageBuffer}

	if buffer_create(shadow_cascades_buffer_ref) == false {
		log.errorf(
			"Failed to create render task '%s' - couldn't create shadow cascades buffer\n",
			doc_name,
		)
		return false
	}

	defer if res == false {
		buffer_destroy(shadow_cascades_buffer_ref)
	}

	bindings := render_task_config_parse_bindings(
		p_render_task_config,
		true,
		{size_of(PrepareShadowCascadesUniformData)},
	) or_return

	render_task_data := new(
		PrepareShadowCascadesRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	defer if res == false {
		free(render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	render_task_name := common.create_name(doc_name)

	compute_job, success := generic_compute_job_create(render_task_name, shader_ref, bindings)
	if success == false {
		log.errorf("Failed to create render task '%s' - couldn't create compute job\n", doc_name)
		return false
	}

	render_task_data.compute_job = compute_job
	render_task_data.shadow_cascades_buffer_ref = shadow_cascades_buffer_ref

	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task.data_ptr = rawptr(render_task_data)

	render_task_data.shadow_map_size = shadow_map_size
	render_task_data.bindings = bindings

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^PrepareShadowCascadesRenderTaskData)(render_task.data_ptr)

	generic_compute_job_destroy(render_task_data.compute_job)
	delete(render_task_data.bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	buffer_destroy(render_task_data.shadow_cascades_buffer_ref)
	delete(render_task_data.bindings, G_RENDERER_ALLOCATORS.resource_allocator)

	free(render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(p_render_task_ref: RenderTaskRef, pdt: f32) {

	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^PrepareShadowCascadesRenderTaskData)(render_task.data_ptr)

	render_views := RenderViews {
		current_view  = render_view_create_from_camera(g_render_camera),
		previous_view = render_view_create_from_camera(g_previous_render_camera),
	}

	global_uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		uniform_buffer_create_view_data(render_views),
		g_uniform_buffers.render_settings_data_offset,
	}

	transition_binding_resources(render_task_data.bindings, .Compute)

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	flags: u32 = 0
	if G_RENDERER_SETTINGS.fit_shadow_cascades {
		flags |= FLAG_FIT_CASCADES
	}
	if G_RENDERER_SETTINGS.stabilize_shadow_cascades {
		flags |= FLAG_STABILIZE_CASCADES
	}

	uniform_data := PrepareShadowCascadesUniformData {
		num_cascades               = G_RENDERER_SETTINGS.num_shadow_cascades,
		shadow_sampling_radius     = G_RENDERER_SETTINGS.directional_light_shadow_sampling_radius,
		split_factor               = CASCADE_SPLIT_LOG_FACTOR,
		aspect_ratio               = f32(
			G_RENDERER.config.render_resolution.x,
		) / f32(G_RENDERER.config.render_resolution.y),
		tan_fov_half               = glsl.tan(0.5 * glsl.radians(g_render_camera.fov)),
		flags                      = flags,
		shadows_rendering_distance = G_RENDERER_SETTINGS.shadows_rendering_distance,
		shadow_map_size            = render_task_data.shadow_map_size,
	}

	task_offsets := []u32{uniform_buffer_create_transient_buffer(&uniform_data)}

	// Create cascade shadow light matrices
	compute_command_dispatch(
		render_task_data.compute_job.compute_command_ref,
		get_frame_cmd_buffer_ref(),
		glsl.uvec3{1, 1, 1},
		{task_offsets, global_uniform_offsets, nil, nil},
		nil,
	)
}

//---------------------------------------------------------------------------//
