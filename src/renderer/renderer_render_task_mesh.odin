package renderer

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	render_pass_ref: RenderPassRef,
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
) -> bool {

	render_pass_ref := find_render_pass_by_name(p_render_task_config["RenderPass"])
	if render_pass_ref == InvalidRenderPassRef {
		return false
	}

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := new(MeshRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	mesh_render_task_data.render_pass_ref = render_pass_ref
	mesh_render_task.data_ptr = rawptr(mesh_render_task_data)

	return true
}

//---------------------------------------------------------------------------//

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	//mesh_render_task_data := (^MeshRenderTaskData)(p_render_task.data_ptr)
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
}

//---------------------------------------------------------------------------//
