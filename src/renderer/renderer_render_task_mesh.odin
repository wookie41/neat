package renderer

//---------------------------------------------------------------------------//

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	render_task_mesh_ref: RenderTaskRef,
}

//---------------------------------------------------------------------------//

create_render_task_mesh :: proc() -> bool {
	INTERNAL.render_task_mesh_ref = allocate_render_task_ref(
		common.create_name("RenderTaskMesh"),
	)
	create_render_task(INTERNAL.render_task_mesh_ref) or_return
	render_task := get_render_task(INTERNAL.render_task_mesh_ref)
	render_task.init = init
	render_task.deinit = deinit
	render_task.begin_frame = begin_frame
	render_task.end_frame = end_frame
	render_task.render = render
	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
init :: proc() -> bool {
	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
deinit :: proc() {

}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc() {
}
//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc() {
}


//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(dt: f32) {
}

//---------------------------------------------------------------------------//
