package renderer

//---------------------------------------------------------------------------//

// This task is responsible for computing the average luminance of the scene
// It's using last frame's scene HDR texture and the histogram approach to calculate avg lum

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

@(private = "file")
THREAD_GROUP_SIZE :: glsl.uvec2{16, 16}

@(private = "file")
ComputeAvgLumRenderTaskData :: struct {
	build_histogram_job:   GenericComputeJob,
	reduce_histogram_job:  GenericComputeJob,
	histogram_buffer_ref:  BufferRef,
	exposure_buffer_ref:   BufferRef,
	scene_hdr_ref:         ImageRef,
	build_shader_bindings: RenderPassBindings,
}

//---------------------------------------------------------------------------//

@(private = "file")
BuildHistogramUniformData :: struct #packed {
	min_lum_log:       f32,
	inv_lum_range_log: f32,
	padding:           glsl.vec2,
}

//---------------------------------------------------------------------------//

@(private = "file")
ReduceHistogramUniformData :: struct #packed {
	min_lum_log:       f32,
	lum_range_log:     f32,
	total_pixel_count: u32,
	exposure_offset:   f32,
	max_ev100_change:  f32,
	padding:           glsl.ivec3,
}

//---------------------------------------------------------------------------//

compute_avg_luminance_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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

	build_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"buildShader",
	) or_return

	reduce_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"reduceShader",
	) or_return

	luminance_histogram_buffer_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"histogramBuffer",
	) or_return

	exposure_buffer_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"exposureBuffer",
	) or_return

	build_shader_ref := shader_find_by_name(build_shader_name)
	if build_shader_ref == InvalidShaderRef {
		return false
	}

	reduce_shader_ref := shader_find_by_name(reduce_shader_name)
	if reduce_shader_ref == InvalidShaderRef {
		return false
	}

	render_task_data := new(ComputeAvgLumRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	defer if res == false {
		free(render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	// Create the histogram buffer
	{
		buffer_ref := buffer_allocate(common.create_name(luminance_histogram_buffer_name))
		buffer := &g_resources.buffers[buffer_get_idx(buffer_ref)]
		buffer.desc.flags = {.Dedicated}
		buffer.desc.size = size_of(u32) * THREAD_GROUP_SIZE.x * THREAD_GROUP_SIZE.x
		buffer.desc.usage = {.StorageBuffer}

		buffer_create(buffer_ref) or_return
		render_task_data.histogram_buffer_ref = buffer_ref
	}
	defer if res == false {
		buffer_destroy(render_task_data.histogram_buffer_ref)
	}

	// Create the avg luminance buffer
	{
		buffer_ref := buffer_allocate(common.create_name(exposure_buffer_name))
		buffer := &g_resources.buffers[buffer_get_idx(buffer_ref)]
		buffer.desc.flags = {.Dedicated}
		buffer.desc.size = size_of(f32) * 3
		buffer.desc.usage = {.StorageBuffer}

		buffer_create(buffer_ref) or_return
		render_task_data.exposure_buffer_ref = buffer_ref
	}
	defer if res == false {
		buffer_destroy(render_task_data.exposure_buffer_ref)
	}

	histogram_buffer := &g_resources.buffers[buffer_get_idx(render_task_data.histogram_buffer_ref)]
	exposure_buffer := &g_resources.buffers[buffer_get_idx(render_task_data.exposure_buffer_ref)]

	// Setup bindings
	render_task_setup_render_pass_bindings(
		p_render_task_config,
		&render_task_data.build_shader_bindings,
		{size_of(BuildHistogramUniformData)},
		{exposure_buffer.desc.size},
		{histogram_buffer.desc.size},
	)
	defer if res == false {
		render_pass_destroy_bindings(render_task_data.build_shader_bindings)
	}

	// Create the build histogram job
	render_task_data.build_histogram_job = generic_compute_job_create(
		common.create_name(doc_name),
		build_shader_ref,
		render_task_data.build_shader_bindings,
		true,
	) or_return

	// Create the reduce job
	{
		bindings := RenderPassBindings {
			buffer_inputs  = {
				{
					buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref,
					offset = common.INVALID_OFFSET,
					size = size_of(ReduceHistogramUniformData),
					usage = .Uniform,
				},
			},
			buffer_outputs = {
				{
					buffer_ref = render_task_data.histogram_buffer_ref,
					size = histogram_buffer.desc.size,
				},
				{
					buffer_ref = render_task_data.exposure_buffer_ref,
					size = exposure_buffer.desc.size,
				},
			},
		}

		render_task_data.reduce_histogram_job = generic_compute_job_create(
			common.create_name("ReduceLuminaceHistogram"),
			reduce_shader_ref,
			bindings,
			false,
		) or_return
	}

	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task.data_ptr = rawptr(render_task_data)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^ComputeAvgLumRenderTaskData)(render_task.data_ptr)

	generic_compute_job_destroy(render_task_data.build_histogram_job)
	generic_compute_job_destroy(render_task_data.reduce_histogram_job)
	render_pass_destroy_bindings(render_task_data.build_shader_bindings)

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
	render_task_data := (^ComputeAvgLumRenderTaskData)(render_task.data_ptr)

	render_view := render_view_create_from_camera(g_render_camera)
	global_uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		uniform_buffer_create_view_data(render_view),
	}

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	lum_min := glsl.log(f32((0.001)))
	lum_max := glsl.log(f32((200000.0)))
	lum_range := (lum_max - lum_min)

	resolution := resolve_resolution(.Full)

	// Build histogram
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Build histogram")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		work_group_count := (resolution + THREAD_GROUP_SIZE) / THREAD_GROUP_SIZE
		uniform_data := BuildHistogramUniformData {
			min_lum_log       = lum_min,
			inv_lum_range_log = 1 / lum_range,
		}

		uniform_data_offset := uniform_buffer_create_transient_buffer(&uniform_data)
		generic_compute_job_uniform_data_offset := generic_compute_job_update_uniform_data(.Full)

		job_uniform_offsets := []u32{generic_compute_job_uniform_data_offset, uniform_data_offset}

		transition_render_pass_resources(render_task_data.build_shader_bindings, .Compute)

		compute_command_dispatch(
			render_task_data.build_histogram_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			nil,
			{job_uniform_offsets, global_uniform_offsets, nil, nil},
			glsl.uvec3{work_group_count.x, work_group_count.y, 1},
		)
	}

	// Reduce histogram
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Reduce histogram")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		histogram_buffer := &g_resources.buffers[buffer_get_idx(render_task_data.histogram_buffer_ref)]
		exposure_buffer := &g_resources.buffers[buffer_get_idx(render_task_data.exposure_buffer_ref)]

		bindings := RenderPassBindings {
			buffer_outputs = {
				{
					buffer_ref = render_task_data.histogram_buffer_ref,
					size = histogram_buffer.desc.size,
					needs_read_barrier = true,
				},
				{
					buffer_ref = render_task_data.exposure_buffer_ref,
					size = exposure_buffer.desc.size,
				},
			},
		}

		uniform_data := ReduceHistogramUniformData {
			min_lum_log       = lum_min,
			lum_range_log     = lum_range,
			total_pixel_count = u32(resolution.x * resolution.y),
			exposure_offset   = 1,
			max_ev100_change  = 2,
		}

		uniform_data_offset := uniform_buffer_create_transient_buffer(&uniform_data)

		job_uniform_offsets := []u32{uniform_data_offset}

		transition_render_pass_resources(bindings, .Compute)

		compute_command_dispatch(
			render_task_data.reduce_histogram_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			nil,
			{job_uniform_offsets, global_uniform_offsets, nil, nil},
			glsl.uvec3{1, 1, 1},
		)
	}
}

//---------------------------------------------------------------------------//
