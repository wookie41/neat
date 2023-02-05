package renderer

//---------------------------------------------------------------------------//

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	mesh_instance_refs: [dynamic]MeshInstanceRef,
}

//---------------------------------------------------------------------------//

create_mesh_render_task :: proc() -> RenderTaskRef {
	mesh_render_task_ref := allocate_render_task_ref(
		common.create_name("MeshRenderTask"),
	)
	if create_render_task(mesh_render_task_ref) == false {
		destroy_render_task(mesh_render_task_ref)
		return InvalidRenderTaskRef
	}
	render_task := get_render_task(mesh_render_task_ref)
	render_task.init = init
	render_task.deinit = deinit
	render_task.begin_frame = begin_frame
	render_task.end_frame = end_frame
	render_task.render = render

	return mesh_render_task_ref
}

//---------------------------------------------------------------------------//

@(private = "file")
init :: proc(p_render_task: ^RenderTaskResource) -> bool {
	// @TODO Replace this with a custom allocator that will allocate only objects of this type
	mesh_render_task_data := new(
		MeshRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	mesh_render_task_data.mesh_instance_refs = make(
		[dynamic]MeshInstanceRef,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_render_task.data_ptr = rawptr(mesh_render_task_data)
	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
deinit :: proc(p_render_task: ^RenderTaskResource) {
	free(p_render_task.data_ptr, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc(p_render_task: ^RenderTaskResource) {
}
//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc(p_render_task: ^RenderTaskResource) {
}


//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(p_render_task: ^RenderTaskResource, dt: f32) {
}

//---------------------------------------------------------------------------//

@(private)
mesh_render_task_add_mesh_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_mesh_instance_ref: MeshInstanceRef,
) {
	render_task := get_render_task(p_render_task_ref)
	mesh_render_task_data := (^MeshRenderTaskData)(render_task.data_ptr)

	append(&mesh_render_task_data.mesh_instance_refs, p_mesh_instance_ref)
}

//---------------------------------------------------------------------------//
