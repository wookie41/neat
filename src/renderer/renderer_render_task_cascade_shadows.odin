package renderer

//---------------------------------------------------------------------------//

import "../common"
import imgui "../third_party/odin-imgui"
import "core:encoding/xml"
import "core:math/linalg/glsl"
import "core:slice"

//---------------------------------------------------------------------------//

@(private)
MAX_SHADOW_CASCADES :: 6 // Keep in sync with scene_types.hlsli

//---------------------------------------------------------------------------//

@(private = "file")
CascadeShadowsRenderTaskData :: struct {
	using material_pass_render_task: MaterialPassRenderTask,
	render_mesh_job:                 RenderInstancedMeshJob,
	num_cascades:                    u32,
	max_shadows_distance:            f32,
	cascades_info_buffer_ref:        BufferRef,
}

//---------------------------------------------------------------------------//

@(private = "file")
ShadowPassConstantData :: struct #packed {
	cascade_index: u32,
	padding:       glsl.uvec3,
}

//---------------------------------------------------------------------------//

cascade_shadows_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
	p_render_task_functions.create_instance = create_instance
	p_render_task_functions.destroy_instance = destroy_instance
	p_render_task_functions.begin_frame = begin_frame
	p_render_task_functions.end_frame = end_frame
	p_render_task_functions.render = render
	p_render_task_functions.draw_debug_ui = draw_debug_ui
}

//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {
	cascade_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	// Parse xml
	name_str := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"name",
	) or_return
	name := common.create_name(name_str)

	num_cascades := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"numCascades",
	) or_return


	cascade_render_task_data := new(
		CascadeShadowsRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	defer if res == false {
		free(cascade_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	bindings := render_task_config_parse_bindings(
		p_render_task_config,
		false,
		{size_of(ShadowPassConstantData)},
	) or_return
	defer delete(bindings, G_RENDERER_ALLOCATORS.resource_allocator)

	render_mesh_job := render_instanced_mesh_job_create(name, bindings) or_return
	defer if res == false {
		render_instanced_mesh_job_destroy(render_mesh_job)
	}

	render_task_init_material_pass_task(
		p_render_task_config,
		render_mesh_job.bind_group_ref,
		&cascade_render_task_data.material_pass_render_task,
	) or_return

	cascade_render_task.data_ptr = rawptr(cascade_render_task_data)
	cascade_render_task_data.render_mesh_job = render_mesh_job
	cascade_render_task_data.num_cascades = num_cascades

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	cascade_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	cascade_render_task_data := (^CascadeShadowsRenderTaskData)(cascade_render_task.data_ptr)

	render_instanced_mesh_job_destroy(cascade_render_task_data.render_mesh_job)
	render_task_destroy_material_pass_task(cascade_render_task_data.material_pass_render_task)

	free(cascade_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
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

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	cascade_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	cascade_render_task_data := (^CascadeShadowsRenderTaskData)(cascade_render_task.data_ptr)

	using cascade_render_task_data

	render_views := make([]RenderViews, num_cascades, temp_arena.allocator)
	outputs_per_view := make([][]RenderPassOutput, num_cascades, temp_arena.allocator)
	shadow_pass_uniform_offsets := make([]u32, num_cascades, temp_arena.allocator)

	for i in 0 ..< num_cascades {

		// Dummy, cascade matrices are calculated by prepare_shadow_cascades
		render_views[i] = {}

		outputs_per_view[i] = slice.clone(
			cascade_render_task_data.render_outputs,
			temp_arena.allocator,
		)
		outputs_per_view[i][0].array_layer = i

		shadow_pass_info := ShadowPassConstantData {
			cascade_index = i,
		}

		shadow_pass_uniform_offsets[i] = uniform_buffer_create_transient_buffer(&shadow_pass_info)
	}

	render_instanced_mesh_job_run(
		cascade_render_task.desc.name,
		cascade_render_task_data.render_mesh_job,
		cascade_render_task_data.render_pass_ref,
		render_views,
		outputs_per_view,
		cascade_render_task_data.material_pass_refs,
		cascade_render_task_data.material_pass_type,
		shadow_pass_uniform_offsets,
	)

	// Transition the cascades for sampling
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_debug_ui :: proc(_: RenderTaskRef) {

	if (imgui.CollapsingHeader("Cascade shadows", {})) {

		imgui.InputInt("Shadow cascade count", (^i32)(&G_RENDERER_SETTINGS.num_shadow_cascades))
		imgui.Checkbox(
			"Draw shadow cascades",
			(^bool)(&G_RENDERER_SETTINGS.debug_draw_shadow_cascades),
		)
		imgui.Checkbox("Fit shadow cascades", (^bool)(&G_RENDERER_SETTINGS.fit_shadow_cascades))
		imgui.Checkbox(
			"Stabilize shadow cascades",
			(^bool)(&G_RENDERER_SETTINGS.stabilize_shadow_cascades),
		)
		imgui.InputFloat(
			"Shadows rendering distance",
			(&G_RENDERER_SETTINGS.shadows_rendering_distance),
		)
		imgui.InputFloat(
			"Direcional light shadow sampling radius",
			(&G_RENDERER_SETTINGS.directional_light_shadow_sampling_radius),
		)

		G_RENDERER_SETTINGS.num_shadow_cascades = max(0, G_RENDERER_SETTINGS.num_shadow_cascades)
		G_RENDERER_SETTINGS.num_shadow_cascades = min(
			G_RENDERER_SETTINGS.num_shadow_cascades,
			MAX_SHADOW_CASCADES,
		)
	}
}
