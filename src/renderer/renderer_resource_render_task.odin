
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//
RenderTaskDesc :: struct {
	name: common.Name,
}

//---------------------------------------------------------------------------//

RenderTaskResource :: struct {
	using backend_render_task: BackendRenderTaskResource,
	desc:                      RenderTaskDesc,
	init:                      proc() -> bool,
	deinit:                    proc(),
	pre_render:                proc(),
	render:                    proc(dt: f32),
}

//---------------------------------------------------------------------------//

RenderTaskRef :: Ref(RenderTaskResource)

//---------------------------------------------------------------------------//

InvalidRenderTaskRef := RenderTaskRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_REF_ARRAY: RefArray(RenderTaskResource)

//---------------------------------------------------------------------------//

init_render_tasks :: proc() -> bool {
	G_RENDER_TASK_REF_ARRAY = create_ref_array(RenderTaskResource, MAX_RENDER_TASKS)
	return backend_init_render_tasks()
}

//---------------------------------------------------------------------------//

deinit_render_tasks :: proc() {
	backend_deinit_render_tasks()
}

//---------------------------------------------------------------------------//

allocate_render_task_ref :: proc(p_name: common.Name) -> RenderTaskRef {
	ref := RenderTaskRef(
		create_ref(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_name),
	)
	get_render_task(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_task :: proc(p_render_task_ref: RenderTaskRef) -> bool {
	render_task := get_render_task(p_render_task_ref)
	if backend_create_render_task(p_render_task_ref, render_task) == false {
		free_ref(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_render_task_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_render_task :: proc(p_ref: RenderTaskRef) -> ^RenderTaskResource {
	return get_resource(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_render_task :: proc(p_ref: RenderTaskRef) {
	render_task := get_render_task(p_ref)
	backend_destroy_render_task(render_task)
	free_ref(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_ref)
}
