
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

RenderTaskDesc :: struct {
	name: common.Name,
	type: RenderTaskType,
}

//---------------------------------------------------------------------------//

RenderTaskRef :: common.Ref(RenderTaskResource)

//---------------------------------------------------------------------------//

RenderTaskType :: enum {
	GenericMesh,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	render_task_functions: map[RenderTaskType]RenderTaskFunctions,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_TYPE_MAPPING := map[string]RenderTaskType {
	"GenericMesh" = .GenericMesh,
}

//---------------------------------------------------------------------------//

RenderTaskResource :: struct {
	desc:     RenderTaskDesc,
	data_ptr: rawptr,
}

//---------------------------------------------------------------------------//

RenderTaskFunctions :: struct {
	// Creates an instance of this render task and all of it's internal resources
	create_instance:  proc(
		p_render_task_ref: RenderTaskRef,
		p_render_task_config: ^RenderTaskConfig,
	) -> bool,
	// Called once, just before destroying the render task
	// This is the place when the render task should destroy it's internal resources
	destroy_instance: proc(p_render_task_ref: RenderTaskRef),
	// Called before the frame begin, i.e. before any draw/compute commands are issued
	begin_frame:      proc(p_render_task_ref: RenderTaskRef),
	// Called after the frame ends, i.e. after all draw and compute commands were submited
	end_frame:        proc(p_render_task_ref: RenderTaskRef),
	// Called each frame to run the render task
	render:           proc(p_render_task_ref: RenderTaskRef, dt: f32),
	// Pointer to data that is internally used but the render task
}

//---------------------------------------------------------------------------//

InvalidRenderTaskRef := RenderTaskRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_REF_ARRAY: common.RefArray(RenderTaskResource)

//---------------------------------------------------------------------------//

RenderTaskConfig :: map[string]string

//---------------------------------------------------------------------------//

init_render_tasks :: proc() -> bool {
	INTERNAL.render_task_functions = make(
		map[RenderTaskType]RenderTaskFunctions,
		len(RenderTaskType),
	)

	G_RENDER_TASK_REF_ARRAY = common.ref_array_create(
		RenderTaskResource,
		MAX_RENDER_TASKS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.render_tasks = make(
		[]RenderTaskResource,
		MAX_RENDER_TASKS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Init mesh render task
	{
		render_task_fn : RenderTaskFunctions
		mesh_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.GenericMesh] = render_task_fn
	}

	return true,
}

//---------------------------------------------------------------------------//

deinit_render_tasks :: proc() {
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		destroy_render_task(G_RENDER_TASK_REF_ARRAY.alive_refs[i])
	}
	common.ref_array_clear(&G_RENDER_TASK_REF_ARRAY)
}

//---------------------------------------------------------------------------//

allocate_render_task_ref :: proc(p_name: common.Name) -> RenderTaskRef {
	ref := RenderTaskRef(common.ref_create(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_name))
	g_resources.render_tasks[get_render_task_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_task :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> bool {
	render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	INTERNAL.render_task_functions[render_task.desc.type].create_instance(p_render_task_ref, p_render_task_config)
	return true
}

//---------------------------------------------------------------------------//

get_render_task_idx :: #force_inline proc(p_ref: RenderTaskRef) -> u32 {
	return common.ref_get_idx(&G_RENDER_TASK_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_render_task :: proc(p_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[get_render_task_idx(p_ref)]
	INTERNAL.render_task_functions[render_task.desc.type].destroy_instance(p_ref)
	common.ref_free(&G_RENDER_TASK_REF_ARRAY, p_ref)
}
