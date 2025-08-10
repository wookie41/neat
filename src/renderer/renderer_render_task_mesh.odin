package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:encoding/xml"

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	using material_pass_render_task: MaterialPassRenderTask,
	render_mesh_job:                 RenderInstancedMeshJob,
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
	mesh_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	mesh_render_task_data := new(MeshRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	defer if res == false {
		free(mesh_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	name_str := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"name",
	) or_return
	name := common.create_name(name_str)

	bindings := render_task_config_parse_bindings(p_render_task_config, {}) or_return
	defer delete(bindings, G_RENDERER_ALLOCATORS.resource_allocator) 

	render_mesh_job := render_instanced_mesh_job_create(name, bindings) or_return
	defer if res == false {
		render_instanced_mesh_job_destroy(render_mesh_job)
	}

	render_task_init_material_pass_task(
		p_render_task_config,
		render_mesh_job.bind_group_ref,
		&mesh_render_task_data.material_pass_render_task,
	) or_return

	mesh_render_task.data_ptr = rawptr(mesh_render_task_data)
	mesh_render_task_data.render_mesh_job = render_mesh_job

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	mesh_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)

	render_instanced_mesh_job_destroy(mesh_render_task_data.render_mesh_job)
	render_task_destroy_material_pass_task(mesh_render_task_data.material_pass_render_task)

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

	mesh_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)

	camera_render_view := render_view_create_from_camera(g_render_camera)

	render_views := []RenderView{camera_render_view}

	render_instanced_mesh_job_run(
		mesh_render_task.desc.name,
		mesh_render_task_data.render_mesh_job,
		mesh_render_task_data.render_pass_ref,
		render_views,
		{mesh_render_task_data.render_outputs},
		mesh_render_task_data.material_pass_refs,
		mesh_render_task_data.material_pass_type,
	)
}

//---------------------------------------------------------------------------//
