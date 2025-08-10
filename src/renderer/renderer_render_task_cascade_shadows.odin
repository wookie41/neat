package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:encoding/xml"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private)
MAX_SHADOW_CASCADES :: 6 // Keep in sync with scene_types.hlsli

//---------------------------------------------------------------------------//

@(private = "file")
CascadeShadowsRenderTaskData :: struct {
	using render_task_common:  RenderTaskCommon,
	render_mesh_job:           RenderInstancedMeshJob,
	num_cascades:              u32,
	max_shadows_distance:      f32,
	cascade_shadows_image_ref: ImageRef,
}

//---------------------------------------------------------------------------//

@(private="file")
ShadowPassConstantData :: struct #packed {
	cascade_index: u32,
	padding: glsl.uvec3,
}

//---------------------------------------------------------------------------//

cascade_shadows_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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
	cascade_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	// Parse xml
	num_cascades := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"numCascades",
	) or_return
	cascades_image_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"cascadesImage",
	) or_return

	cascade_render_task_data := new(
		CascadeShadowsRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	cascade_render_task_data.cascade_shadows_image_ref = image_find(cascades_image_name)

	render_mesh_job := render_instanced_mesh_job_create(size_of(ShadowPassConstantData)) or_return

	cascade_render_task.data_ptr = rawptr(cascade_render_task_data)
	cascade_render_task_data.render_mesh_job = render_mesh_job
	cascade_render_task_data.num_cascades = num_cascades

	defer if res == false {
		free(cascade_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	// Update global bind group with the cascade image
	for i in 0 ..< MAX_SHADOW_CASCADES {

		update := BindGroupUpdate {
			images = {
				{
					binding = u32(GlobalResourceSlot.CascadeShadowTextureArray),
					image_ref = cascade_render_task_data.cascade_shadows_image_ref,
					base_array = u32(i),
					array_element = u32(i),
					layer_count = 1,
					mip_count = 1,
					flags = {.AddressSubresource},
				},
			},
		}

		if i >= int(num_cascades) {
			update.images[0].base_array = 0
		}
		
		bind_group_update(G_RENDERER.globals_bind_group_ref, update)
	}

	return render_task_common_init(
		p_render_task_config,
		render_mesh_job.bind_group_ref,
		&cascade_render_task_data.render_task_common,
		{},
		{size_of(ShadowCascade) * MAX_SHADOW_CASCADES},
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	cascade_render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	cascade_render_task_data := (^CascadeShadowsRenderTaskData)(cascade_render_task.data_ptr)
	if cascade_render_task_data != nil {
		delete(
			cascade_render_task_data.material_pass_refs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	if cascade_render_task_data.render_pass_bindings.image_inputs != nil {
		delete(
			cascade_render_task_data.render_pass_bindings.image_inputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	if cascade_render_task_data.render_pass_bindings.image_outputs != nil {
		delete(
			cascade_render_task_data.render_pass_bindings.image_outputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
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

	render_views := make([]RenderView, num_cascades, temp_arena.allocator)
	render_pass_bindings_per_view := make([]RenderPassBindings, num_cascades, temp_arena.allocator)
	shadow_pass_uniform_offsets := make([]u32, num_cascades, temp_arena.allocator)

	for i in 0 ..< num_cascades {

		// Dummy, cascade matrices are calculated by prepare_shadow_cascades
		render_views[i] = {
			view       = glsl.mat4(0),
			projection = glsl.mat4(0),
		}

		render_pass_bindings_per_view[i] = create_cascade_render_pass_bindings(
			cascade_shadows_image_ref,
			u32(i),
			temp_arena.allocator,
		)

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
		render_pass_bindings_per_view,
		cascade_render_task_data.material_pass_refs,
		cascade_render_task_data.material_pass_type,
		shadow_pass_uniform_offsets,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
create_cascade_render_pass_bindings :: proc(
	p_cascade_image_ref: ImageRef,
	p_cascade_index: u32,
	p_allocator: mem.Allocator,
) -> RenderPassBindings {

	render_pass_bindings := RenderPassBindings {
		image_outputs = make([]RenderPassImageOutput, 1, p_allocator),
	}

	render_pass_bindings.image_outputs[0] = RenderPassImageOutput {
		image_ref   = p_cascade_image_ref,
		array_layer = p_cascade_index,
		flags       = {.Clear},
	}

	return render_pass_bindings
}

//---------------------------------------------------------------------------//
