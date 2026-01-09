package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"
import "core:strings"

//---------------------------------------------------------------------------//

@(private = "file")
THREAD_GROUP_SIZE :: glsl.uvec2{8, 8}

//---------------------------------------------------------------------------//

@(private = "file")
FullScreenRenderTaskData :: struct {
	compute_job:         GenericComputeJob,
	pixel_job:           GenericPixelJob,
	resolution:          Resolution,
	bindings:            []Binding,
	render_pass_outputs: []RenderPassOutput,
	is_using_compute:    bool,
}

//---------------------------------------------------------------------------//

fullscreen_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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

	resolution_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"resolution",
	) or_return
	if (resolution_name in G_RESOLUTION_NAME_MAPPING) == false {
		log.errorf("Failed to create render task '%s' - unsupported resolution \n", doc_name)
		return false
	}

	shader_ref := shader_find_by_name(shader_name)
	if shader_ref == InvalidShaderRef {
		log.errorf("Failed to create render task '%s' - invalid shader\n", doc_name)
		return false
	}

	fullscreen_render_task_data := new(
		FullScreenRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	defer if res == false {
		free(fullscreen_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	fullscreen_render_task_data.resolution = G_RESOLUTION_NAME_MAPPING[resolution_name]
	fullscreen_render_task_data.is_using_compute = strings.has_suffix(shader_name, ".comp")

	render_task_name := common.create_name(doc_name)

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	if fullscreen_render_task_data.is_using_compute {

		fullscreen_render_task_data.bindings = render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(GenericComputeJobUniformData)},
		) or_return

		compute_job, success := generic_compute_job_create(
			render_task_name,
			shader_ref,
			fullscreen_render_task_data.bindings,
		)
		if success == false {
			log.errorf(
				"Failed to create render task '%s' - couldn't create compute job\n",
				doc_name,
			)
			return false
		}
		fullscreen_render_task_data.compute_job = compute_job
	} else {

		fullscreen_render_task_data.bindings = render_task_config_parse_bindings(
			p_render_task_config,
			false,
			{size_of(GenericComputeJobUniformData)},
		) or_return

		fullscreen_render_task_data.render_pass_outputs = parse_output_images(
			p_render_task_config,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		pixel_job, success := generic_pixel_job_create(
			render_task_name,
			shader_ref,
			fullscreen_render_task_data.bindings,
			fullscreen_render_task_data.render_pass_outputs,
			resolve_resolution(fullscreen_render_task_data.resolution),
		)
		if success == false {
			log.errorf("Failed to create render task '%s' - couldn't create pixel job\n", doc_name)
			return false
		}
		fullscreen_render_task_data.pixel_job = pixel_job
	}

	fullscreen_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	fullscreen_render_task.data_ptr = rawptr(fullscreen_render_task_data)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	fullscreen_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	fullscreen_render_task_data := (^FullScreenRenderTaskData)(fullscreen_render_task.data_ptr)

	if fullscreen_render_task_data.is_using_compute {
		generic_compute_job_destroy(fullscreen_render_task_data.compute_job)
	} else {
		generic_pixel_job_destroy(fullscreen_render_task_data.pixel_job)
	}

	delete(fullscreen_render_task_data.bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(
		fullscreen_render_task_data.render_pass_outputs,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	free(fullscreen_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
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

	fullscreen_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	fullscreen_render_task_data := (^FullScreenRenderTaskData)(fullscreen_render_task.data_ptr)

	render_views := RenderViews {
		current_view  = render_view_create_from_camera(g_render_camera),
		previous_view = render_view_create_from_camera(g_previous_render_camera),
	}

	global_uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		uniform_buffer_create_view_data(render_views),
		g_uniform_buffers.render_settings_data_offset,
	}

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), fullscreen_render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	transition_binding_resources(
		fullscreen_render_task_data.bindings,
		.Compute if fullscreen_render_task_data.is_using_compute else .Graphics,
	)

	fullscreen_task_uniform_data_offset := generic_compute_job_create_uniform_data(
		fullscreen_render_task_data.resolution,
	)
	per_instance_offsets := []u32{fullscreen_task_uniform_data_offset}

	if fullscreen_render_task_data.is_using_compute {

		resolution := resolve_resolution(fullscreen_render_task_data.resolution)

		bind_group_update(
			fullscreen_render_task_data.compute_job.bind_group_ref,
			fullscreen_render_task_data.bindings,
		)

		// Dispatch the command
		work_group_count := (resolution + THREAD_GROUP_SIZE) / THREAD_GROUP_SIZE

		compute_command_dispatch(
			fullscreen_render_task_data.compute_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			glsl.uvec3{work_group_count.x, work_group_count.y, 1},
			{per_instance_offsets, global_uniform_offsets, nil, nil},
			nil,
		)

		return
	}

	bind_group_update(
		fullscreen_render_task_data.pixel_job.bind_group_ref,
		fullscreen_render_task_data.bindings,
	)

	render_task_render_pass_begin(
		fullscreen_render_task_data.pixel_job.render_pass_ref,
		fullscreen_render_task_data.render_pass_outputs,
	)

	draw_command_execute(
		fullscreen_render_task_data.pixel_job.draw_command_ref,
		get_frame_cmd_buffer_ref(),
		nil,
		{per_instance_offsets, global_uniform_offsets, nil, nil},
	)

	render_pass_end(
		fullscreen_render_task_data.pixel_job.render_pass_ref,
		get_frame_cmd_buffer_ref(),
	)
}

//---------------------------------------------------------------------------//
