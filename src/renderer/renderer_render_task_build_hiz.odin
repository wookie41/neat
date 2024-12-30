package renderer

//---------------------------------------------------------------------------//

// This task is responsible for building the Hi-Z Buffer
// It's using the AMD SPD to build the mip-chain in one pass

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

@(private = "file")
THREAD_GROUP_SIZE :: glsl.uvec2{256, 1}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	hiz_bind_group_layout_ref: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

@(private = "file")
HiZRenderTaskData :: struct {
	compute_job:                   GenericComputeJob,
	render_pass_bindings:          RenderPassBindings,
	resolution:                    Resolution,
	hiz_ref:                       ImageRef,
	spd_atomic_counter_buffer_ref: BufferRef,
	mip_count:                     u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
HiZUniformData :: struct #packed {
	hiz_buffer_dimensions: glsl.uvec2,
	mip_count:             u32,
	work_group_count:      u32,
}

//---------------------------------------------------------------------------//

build_hiz_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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

	hiz_buffer_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"hiZBuffer",
	) or_return
	spd_counter_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"counterBuffer",
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

	shader_ref := find_shader_by_name(shader_name)
	if shader_ref == InvalidShaderRef {
		log.errorf("Failed to create render task '%s' - invalid shader %s\n", doc_name, shader_name)
		return false
	}

	hiz_render_task_data := new(HiZRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	defer if res == false {
		free(hiz_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
		render_pass_bindings_destroy(hiz_render_task_data.render_pass_bindings)
	}

	hiz_render_task_data.resolution = G_RESOLUTION_NAME_MAPPING[resolution_name]

	resolution := resolve_resolution(hiz_render_task_data.resolution)
	log2Size := linalg.min(
		linalg.log2(glsl.vec2{f32(resolution.x), f32(resolution.y)}),
		glsl.vec2(12),
	) // clamp to SPD 

	// Create the HiZ buffer
	hiz_ref := allocate_image_ref(common.create_name(hiz_buffer_name))
	hiz := &g_resources.images[get_image_idx(hiz_ref)]
	hiz.desc.dimensions = glsl.uvec3{resolution.x, resolution.y, 1}
	hiz.desc.mip_count = u32(linalg.ceil(linalg.max(log2Size.x, log2Size.y)))
	hiz.desc.array_size = 1
	hiz.desc.flags = {.Sampled, .Storage}
	hiz.desc.format = .R32SFloat
	hiz.desc.type = .TwoDimensional
	hiz.desc.sample_count_flags = {._1}

	if create_image(hiz_ref) == false {
		log.errorf("Failed to create render task '%s' - couldn't create HiZ\n", doc_name)
		return false
	}

	defer if res == false {
		destroy_image(hiz_ref)
	}

	// Create the SPD atomic counter buffer
	spd_atomic_counter_buffer_ref := allocate_buffer_ref(common.create_name(spd_counter_name))
	spd_atomic_counter_buffer := &g_resources.buffers[get_buffer_idx(spd_atomic_counter_buffer_ref)]
	spd_atomic_counter_buffer.desc.flags = {.Dedicated}
	spd_atomic_counter_buffer.desc.size = size_of(u32) * 6
	spd_atomic_counter_buffer.desc.usage = {.StorageBuffer}

	if create_buffer(spd_atomic_counter_buffer_ref) == false {
		log.errorf("Failed to create render task '%s' - couldn't create SPD counter\n", doc_name)
		return false
	}

	defer if res == false {
		destroy_buffer(spd_atomic_counter_buffer_ref)
	}

	// Setup render task bindings
	render_task_setup_render_pass_bindings(
		p_render_task_config,
		&hiz_render_task_data.render_pass_bindings,
		{size_of(HiZUniformData)},
		{},
		{spd_atomic_counter_buffer.desc.size},
	)

	hiz_render_task_data.mip_count = hiz.desc.mip_count

	render_task_name := common.create_name(doc_name)

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	compute_job, success := generic_compute_job_create(
		render_task_name,
		shader_ref,
		hiz_render_task_data.render_pass_bindings,
	)
	if success == false {
		log.errorf("Failed to create render task '%s' - couldn't create compute job\n", doc_name)
		return false
	}
	hiz_render_task_data.compute_job = compute_job
	hiz_render_task_data.hiz_ref = hiz_ref

	hiz_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	hiz_render_task.data_ptr = rawptr(hiz_render_task_data)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	hiz_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	hiz_render_task_data := (^HiZRenderTaskData)(hiz_render_task.data_ptr)

	generic_compute_job_destroy(hiz_render_task_data.compute_job)
	render_pass_bindings_destroy(hiz_render_task_data.render_pass_bindings)
	destroy_image(hiz_render_task_data.hiz_ref)
	destroy_buffer(hiz_render_task_data.spd_atomic_counter_buffer_ref)

	free(hiz_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
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

	hiz_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	hiz_render_task_data := (^HiZRenderTaskData)(hiz_render_task.data_ptr)

	render_view := render_camera_create_render_view(g_render_camera)

	global_uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		uniform_buffer_create_view_data(render_view),
	}

	// Perform resource transitions
	transition_render_pass_resources(hiz_render_task_data.render_pass_bindings, .Compute)

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), hiz_render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	hiz_resolution := resolve_resolution(hiz_render_task_data.resolution)
	depth_resolution := resolve_resolution(.Full)

	work_group_count := glsl.uvec2{(depth_resolution.x + 63) >> 6, (depth_resolution.y + 63) >> 6}
	hiz_uniform_data := HiZUniformData {
		hiz_buffer_dimensions = hiz_resolution,
		mip_count             = hiz_render_task_data.mip_count,
		work_group_count      = work_group_count.x * work_group_count.y,
	}

	hiz_uniform_data_offset := uniform_buffer_create_transient_buffer(&hiz_uniform_data)
	generic_compute_job_uniform_data_offset := generic_compute_job_update_uniform_data(.Full)

	// Dispatch the command
	per_instance_offsets := []u32{generic_compute_job_uniform_data_offset, hiz_uniform_data_offset}

	compute_command_dispatch(
		hiz_render_task_data.compute_job.compute_command_ref,
		get_frame_cmd_buffer_ref(),
		nil,
		{per_instance_offsets, global_uniform_offsets, nil, nil},
		glsl.uvec3{work_group_count.x, work_group_count.y, 1},
	)
}

//---------------------------------------------------------------------------//
