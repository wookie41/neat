package renderer

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	using render_task_common: RenderTaskCommon,
	render_mesh_job:          RenderInstancedMeshJob,
}

//---------------------------------------------------------------------------//

mesh_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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
	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]

	render_mesh_job := render_instanced_mesh_job_create() or_return

	mesh_render_task_data := new(MeshRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	mesh_render_task.data_ptr = rawptr(mesh_render_task_data)
	mesh_render_task_data.render_mesh_job = render_mesh_job

	defer if res == false {
		free(mesh_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	return render_task_common_init(
		p_render_task_config, 
		render_mesh_job.bind_group_ref, 
		&mesh_render_task_data.render_task_common)
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)
	if mesh_render_task_data != nil {
		delete(mesh_render_task_data.material_pass_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	if mesh_render_task_data.render_pass_bindings.image_inputs != nil {
		delete(
			mesh_render_task_data.render_pass_bindings.image_inputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	if mesh_render_task_data.render_pass_bindings.image_outputs != nil {
		delete(
			mesh_render_task_data.render_pass_bindings.image_outputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	free(mesh_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
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

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)

	camera_render_view := render_camera_create_render_view(g_render_camera)

	render_views := []RenderView {camera_render_view}
	bindings_per_view := []RenderPassBindings{mesh_render_task_data.render_pass_bindings}

	render_instanced_mesh_job_run(
		mesh_render_task.desc.name,
		mesh_render_task_data.render_mesh_job,
		mesh_render_task_data.render_pass_ref,
		render_views,
		bindings_per_view,
		mesh_render_task_data.material_pass_refs,
		mesh_render_task_data.material_pass_type,
	)
}

//---------------------------------------------------------------------------//
