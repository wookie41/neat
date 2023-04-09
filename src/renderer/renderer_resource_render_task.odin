
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
	// Called once, after creating the render task
	// This is the place when the render task should create it's internal resources
	init:                      proc(p_render_task: ^RenderTaskResource) -> bool,
	// Called once, just before destroying the render task
	// This is the place when the render task should destroy it's internal resources
	deinit:                    proc(p_render_task: ^RenderTaskResource),
	// Called before the frame begin, i.e. before any draw/compute commands are issued
	begin_frame:               proc(p_render_task: ^RenderTaskResource),
	// Called after the frame ends, i.e. after all draw and compute commands were submited
	end_frame:                 proc(p_render_task: ^RenderTaskResource),
	// Called each frame to run the render task
	render:                    proc(p_render_task: ^RenderTaskResource, dt: f32),
	// Pointer to data that is internally used but the render task
	data_ptr:                  rawptr,
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

RenderTaskConfig :: map[string]string

//---------------------------------------------------------------------------//

init_render_tasks :: proc() -> bool {
	G_RENDER_TASK_REF_ARRAY = create_ref_array(RenderTaskResource, MAX_RENDER_TASKS)
	return backend_init_render_tasks()
}

//---------------------------------------------------------------------------//

deinit_render_tasks :: proc() {
	backend_deinit_render_tasks()
	for render_task_ref in G_RENDER_TASK_REF_ARRAY.alive_refs {
		render_task := get_render_task(render_task_ref)
		render_task.deinit(render_task)
		destroy_render_task(render_task_ref)
	}
	clear_ref_array(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY)
}

//---------------------------------------------------------------------------//

@(private)
RENDER_TASK_CREATE_FUNCTION_BY_NAME := map[string]proc(p_render_task_config: RenderTaskConfig) -> RenderTaskRef {
	"Mesh" = create_mesh_render_task,
}

//---------------------------------------------------------------------------//

allocate_render_task_ref :: proc(p_name: common.Name) -> RenderTaskRef {
	ref := RenderTaskRef(create_ref(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_name))
	get_render_task(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_task :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: RenderTaskConfig,
) -> bool {
	render_task := get_render_task(p_render_task_ref)
	if backend_create_render_task(p_render_task_ref, render_task, p_render_task_config) == false {
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
