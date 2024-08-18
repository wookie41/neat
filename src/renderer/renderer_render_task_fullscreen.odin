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
INTERNAL: struct {
	fullscreen_bind_group_layout_ref: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

@(private = "file")
FullScreenRenderTaskData :: struct {
	render_pass_bindings: RenderPassBindings,
	bind_group_ref:       BindGroupRef,
	draw_command_ref:     DrawCommandRef,
	compute_command_ref:  ComputeCommandRef,
	render_pass_ref:      RenderPassRef,
	resolution:           Resolution,
}

//---------------------------------------------------------------------------//

@(private = "file")
FullScreenTaskUniformData :: struct #packed {
	input_size: glsl.vec4, // xy: rpc of input size, zw: input size
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


	shader_ref := find_shader_by_name(shader_name)
	if shader_ref == InvalidShaderRef {
		log.errorf("Failed to create render task '%s' - invalid shader\n", doc_name)
		return false
	}

	// Setup render task bindings
	render_pass_bindings: RenderPassBindings
	render_task_setup_render_pass_bindings(p_render_task_config, &render_pass_bindings)

	defer if res == false {
		delete(render_pass_bindings.image_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	fullscreen_render_task_data := new(
		FullScreenRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	defer if res == false {
		free(fullscreen_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	fullscreen_render_task_data.resolution = G_RESOLUTION_NAME_MAPPING[resolution_name]

	is_using_compute := false
	shader_stages := ShaderStageFlags{}

	render_task_name := common.create_name(doc_name)

	if strings.has_suffix(shader_name, ".comp") {
		is_using_compute = true
		shader_stages += {.Compute}
		assert(len(render_pass_bindings.image_outputs) == 0)
	} else if strings.has_suffix(shader_name, ".pix") {
		shader_stages += {.Pixel}

		// Create a render pass based on output imagess
		fullscreen_render_task_data.render_pass_ref = allocate_render_pass_ref(
			render_task_name,
			len(render_pass_bindings.image_outputs),
		)
		render_pass := &g_resources.render_passes[get_render_pass_idx(fullscreen_render_task_data.render_pass_ref)]
		render_pass.desc.depth_stencil_type = .None
		render_pass.desc.primitive_type = .TriangleList
		render_pass.desc.resterizer_type = .Fill
		render_pass.desc.multisampling_type = ._1
		render_pass.desc.resolution = fullscreen_render_task_data.resolution

		for output_image, i in render_pass_bindings.image_outputs {
			image := &g_resources.images[get_image_idx(output_image.image_ref)]
			render_pass.desc.layout.render_target_formats[i] = image.desc.format
			render_pass.desc.layout.render_target_blend_types[i] = .Default
		}

		create_render_pass(fullscreen_render_task_data.render_pass_ref) or_return

	} else {
		assert(false, "Unsupported fullscreen shader type")
	}


	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)


	// Create a bind group layout for the fullscreen pass based on the input images and buffers
	INTERNAL.fullscreen_bind_group_layout_ref = allocate_bind_group_layout_ref(
		common.create_name("FullScreenBindGroupLayout"),
		u32(len(render_pass_bindings.image_inputs)) + (1 if is_using_compute else 0),
	)
	bind_group_layout := &g_resources.bind_group_layouts[get_bind_group_layout_idx(INTERNAL.fullscreen_bind_group_layout_ref)]

	binding_index := 0

	// First entry for compute path contains the uniform buffer with the output texture size
	if is_using_compute {
		bind_group_layout.desc.bindings[0].count = 1
		bind_group_layout.desc.bindings[0].shader_stages = {.Compute}
		bind_group_layout.desc.bindings[0].type = .UniformBufferDynamic

		binding_index += 1
	}

	for input_image in render_pass_bindings.image_inputs {
		bind_group_layout.desc.bindings[binding_index].count = 1
		bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stages
		bind_group_layout.desc.bindings[binding_index].type =
			.StorageImage if .Storage in input_image.flags else .Image

		binding_index += 1
	}

	if create_bind_group_layout(INTERNAL.fullscreen_bind_group_layout_ref) == false {
		destroy_bind_group_layout(INTERNAL.fullscreen_bind_group_layout_ref)
		log.error("Failed to create bind group layout for the fullscreen pass")
		assert(false)
	}

	// Create a bind group for the task based on the created layout
	bind_group_ref := allocate_bind_group_ref(render_task_name)
	bind_group := &g_resources.bind_groups[get_bind_group_idx(bind_group_ref)]

	bind_group.desc.layout_ref = INTERNAL.fullscreen_bind_group_layout_ref

	create_bind_group(bind_group_ref) or_return // @TODO delete the bind group layout or just don't allow this to fail

	// Update the bind group with the images from the render tasks bindings
	fullscreen_bind_group_update := BindGroupUpdate {
		images = make(
			[]BindGroupImageBinding,
			len(render_pass_bindings.image_inputs),
			temp_arena.allocator,
		),
	}

	for input_image, i in render_pass_bindings.image_inputs {
		fullscreen_bind_group_update.images[i] = BindGroupImageBinding {
			image_ref = input_image.image_ref,
			mip       = input_image.mip,
		}
	}

	if is_using_compute {
		fullscreen_bind_group_update.buffers = {
			{
				buffer_ref = g_uniform_buffers.per_instance_buffer_ref,
				size = size_of(FullScreenTaskUniformData),
			},
		}
	}

	bind_group_update(bind_group_ref, fullscreen_bind_group_update)

	// Create the compute command or draw command for the task
	if is_using_compute {

		// Compute path

		compute_command_ref := compute_command_allocate_ref(render_task_name, 4, 0)
		compute_command := &g_resources.compute_commands[compute_command_get_idx(compute_command_ref)]

		compute_command.desc.bind_group_layout_refs[0] = INTERNAL.fullscreen_bind_group_layout_ref
		compute_command.desc.bind_group_layout_refs[1] = G_RENDERER.uniforms_bind_group_layout_ref
		compute_command.desc.bind_group_layout_refs[2] = G_RENDERER.globals_bind_group_layout_ref
		compute_command.desc.bind_group_layout_refs[3] = G_RENDERER.bindless_bind_group_layout_ref

		compute_command.desc.compute_shader_ref = shader_ref

		compute_command_create(compute_command_ref)

		compute_command_set_bind_group(compute_command_ref, 0, bind_group_ref)
		compute_command_set_bind_group(compute_command_ref, 1, G_RENDERER.uniforms_bind_group_ref)
		compute_command_set_bind_group(compute_command_ref, 2, G_RENDERER.globals_bind_group_ref)
		compute_command_set_bind_group(compute_command_ref, 3, G_RENDERER.bindless_bind_group_ref)

		fullscreen_render_task_data.compute_command_ref = compute_command_ref
		fullscreen_render_task_data.draw_command_ref = InvalidDrawCommandRef
	} else {

		// Compute

		draw_command_ref := draw_command_allocate_ref(render_task_name, 4, 0)
		draw_command := &g_resources.draw_commands[draw_command_get_idx(draw_command_ref)]

		draw_command.desc.bind_group_layout_refs[0] = INTERNAL.fullscreen_bind_group_layout_ref
		draw_command.desc.bind_group_layout_refs[1] = G_RENDERER.uniforms_bind_group_layout_ref
		draw_command.desc.bind_group_layout_refs[2] = G_RENDERER.globals_bind_group_layout_ref
		draw_command.desc.bind_group_layout_refs[3] = G_RENDERER.bindless_bind_group_layout_ref

		draw_command.desc.vert_shader_ref = find_shader_by_name("fullscreen.vert")
		draw_command.desc.frag_shader_ref = shader_ref
		draw_command.desc.draw_count = 3
		draw_command.desc.vertex_layout = .Empty

		draw_command_create(draw_command_ref, fullscreen_render_task_data.render_pass_ref)

		draw_command_set_bind_group(draw_command_ref, 0, bind_group_ref)
		draw_command_set_bind_group(draw_command_ref, 1, G_RENDERER.uniforms_bind_group_ref)
		draw_command_set_bind_group(draw_command_ref, 2, G_RENDERER.globals_bind_group_ref)
		draw_command_set_bind_group(draw_command_ref, 3, G_RENDERER.bindless_bind_group_ref)

		fullscreen_render_task_data.draw_command_ref = draw_command_ref
		fullscreen_render_task_data.compute_command_ref = InvalidComputeCommandRef
	}

	// Set render task data
	fullscreen_render_task_data.render_pass_bindings = render_pass_bindings

	fullscreen_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	fullscreen_render_task.data_ptr = rawptr(fullscreen_render_task_data)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	fullscreen_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	fullscreen_render_task_data := (^FullScreenRenderTaskData)(fullscreen_render_task.data_ptr)
	if fullscreen_render_task_data.render_pass_bindings.image_inputs != nil {
		delete(
			fullscreen_render_task_data.render_pass_bindings.image_inputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	free(fullscreen_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	destroy_bind_group(fullscreen_render_task_data.bind_group_ref)
	if fullscreen_render_task_data.draw_command_ref != InvalidDrawCommandRef {
		draw_command_destroy(fullscreen_render_task_data.draw_command_ref)
		destroy_render_pass(fullscreen_render_task_data.render_pass_ref)
	} else if fullscreen_render_task_data.compute_command_ref != InvalidComputeCommandRef {
		compute_command_destroy(fullscreen_render_task_data.compute_command_ref)
	}
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
render :: proc(p_render_task_ref: RenderTaskRef, dt: f32) {

	fullscreen_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	fullscreen_render_task_data := (^FullScreenRenderTaskData)(fullscreen_render_task.data_ptr)

	use_compute := fullscreen_render_task_data.compute_command_ref != InvalidComputeCommandRef

	global_uniform_offsets := []u32{
		uniform_buffer_management_get_per_frame_offset(),
		uniform_buffer_management_get_per_view_offset(),
	}

	// Perform resource transitions
	transition_resources(
		get_frame_cmd_buffer_ref(),
		&fullscreen_render_task_data.render_pass_bindings,
		.Compute if use_compute else .Graphics,
	)

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), fullscreen_render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	if use_compute {

		resolution := get_resolution(fullscreen_render_task_data.resolution)

		// Upload uniform data
		fullscreen_task_uniform_data := FullScreenTaskUniformData {
			input_size = glsl.vec4{
				1.0 / f32(resolution.x),
				1.0 / f32(resolution.y),
				f32(resolution.x),
				f32(resolution.y),
			},
		}

		fullscreen_task_uniform_data_offset := uniform_buffer_management_request_per_instance_data(
			&fullscreen_task_uniform_data,
			size_of(fullscreen_task_uniform_data),
		)

		// Dispatch the command
		per_instance_offsets := []u32{fullscreen_task_uniform_data_offset}
		work_group_count := (resolution + THREAD_GROUP_SIZE) / THREAD_GROUP_SIZE

		compute_command_dispatch(
			fullscreen_render_task_data.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			nil,
			{per_instance_offsets, global_uniform_offsets, nil, nil},
			glsl.uvec3{work_group_count.x, work_group_count.y, 1},
		)

		return
	}


	render_task_begin_render_pass(
		fullscreen_render_task_data.render_pass_ref,
		&fullscreen_render_task_data.render_pass_bindings,
	)

	draw_command_execute(
		fullscreen_render_task_data.draw_command_ref,
		get_frame_cmd_buffer_ref(),
		nil,
		{nil, global_uniform_offsets, nil, nil},
	)

	end_render_pass(fullscreen_render_task_data.render_pass_ref, get_frame_cmd_buffer_ref())
}

//---------------------------------------------------------------------------//
