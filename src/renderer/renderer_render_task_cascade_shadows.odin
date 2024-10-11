package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
MAX_CASCADES :: 6

@(private = "file")
CASCADE_SPLIT_LOG_FACTOR :: 0.90

//---------------------------------------------------------------------------//

@(private = "file")
CascadeShadowsRenderTaskData :: struct {
	using render_task_common: RenderTaskCommon,
	render_mesh_job:          RenderInstancedMeshJob,
	num_cascades:             u32,
	max_shadows_distance:     f32,
	cascade_depth_image_refs: [MAX_CASCADES]ImageRef,
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

@(private)
g_cascade_shadows_data: struct {
	cascade_matrices: [MAX_CASCADES]glsl.mat4,
}

//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {
	cascade_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	// Parse xml
	num_cascades := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"numCascades",
	) or_return

	resolution := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"resolution",
	) or_return

	max_shadows_distance := common.xml_get_f32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"maxShadowsDistance",
	) or_return

	cascade_images_refs: [MAX_CASCADES]ImageRef

	// Create depth images for cascades
	for i in 0 ..< num_cascades {

		image_ref := allocate_image_ref(
			common.create_name(common.aprintf(temp_arena.allocator, "Cascade[%d]", i)),
		)
		image_idx := get_image_idx(image_ref)
		image := &g_resources.images[image_idx]

		image.desc.dimensions = {resolution, resolution, 1}
		image.desc.flags = {.Sampled}
		image.desc.type = .TwoDimensional
		image.desc.format = .Depth32SFloat
		image.desc.mip_count = 1

		create_image(image_ref) or_return

		cascade_images_refs[i] = image_ref
	}

	defer if res == false {
		for i in 0 ..< num_cascades {
			destroy_image(cascade_images_refs[i])
			if cascade_images_refs[i] == InvalidImageRef {
				break
			}
		}
	}

	render_mesh_job := render_instanced_mesh_job_create() or_return

	cascade_render_task_data := new(
		CascadeShadowsRenderTaskData,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	cascade_render_task.data_ptr = rawptr(cascade_render_task_data)
	cascade_render_task_data.render_mesh_job = render_mesh_job
	cascade_render_task_data.num_cascades = num_cascades
	cascade_render_task_data.cascade_depth_image_refs = cascade_images_refs
	cascade_render_task_data.max_shadows_distance = max_shadows_distance

	defer if res == false {
		free(cascade_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	return render_task_common_init(
		p_render_task_config,
		render_mesh_job.bind_group_ref,
		&cascade_render_task_data.render_task_common,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	cascade_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
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

	cascade_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	cascade_render_task_data := (^CascadeShadowsRenderTaskData)(cascade_render_task.data_ptr)

	using cascade_render_task_data

	render_views := make([]RenderView, num_cascades, temp_arena.allocator)
	render_pass_bindings_per_view := make([]RenderPassBindings, num_cascades, temp_arena.allocator)

	// Calculation of the cascade planes based on
	// https://developer.download.nvidia.com/SDK/10.5/opengl/src/cascaded_shadow_maps/doc/cascaded_shadow_maps.pdf

	camera_near := g_render_camera.near_plane

	// First, calculate the far splits
	cascade_splits: [MAX_CASCADES]f32
	for i in 0 ..< num_cascades {
		cascade_splits[i] =
			camera_near + ((max_shadows_distance - camera_near) * (f32(i) + 1) / f32(num_cascades))
	}

	cascade_near := camera_near

	camera_aspect_ratio :=
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y)

	coordinate_system_correction := glsl.mat4{
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, -0.5, 0.0,
		0.0, 0.0,  0.5, 1.0,
	}

	for i in 0 ..< num_cascades {

		cascade_far := cascade_splits[i]

		// Calculate points of the view frustum capped to this cascade's near and far planes
		// @TODO Tightly fit this on the GPU based on depth buffer
		frustum_points, frustum_center := common.compute_frustum_points(
			cascade_near,
			cascade_far,
			camera_aspect_ratio,
			g_render_camera.fov,
			g_render_camera.position,
			g_render_camera.forward,
			g_render_camera.up,
		)		

		// Calculate the view matrix for the light
		up := glsl.vec3{0, -1, 0} if glsl.abs(g_per_frame_data.sun.direction.y) < 0.999 else glsl.vec3{0, 0, -1}

		view := glsl.mat4LookAt(frustum_center, frustum_center - g_per_frame_data.sun.direction, up)

		// Find the min and max point of the frustum computed above in light space
		// and based on the build the projection matrix. Thanks to that, we won't be
		// wasting texture space for parts that will not have anything drawn, thus 
		// the precision will also be better
		min_p := glsl.vec3(max(f32))
		max_p := glsl.vec3(min(f32))

		for p in frustum_points {
			pv := view * glsl.vec4{p.x, p.y, p.z, 1}
			pv2 := glsl.vec3{pv.x, pv.y, pv.z}
			min_p = glsl.min(min_p, pv2)
			max_p = glsl.max(max_p, pv2)
		}

		scale := glsl.vec3(2) / (max_p - min_p)
		offset := -0.5 * (max_p + min_p) * scale

		proj := glsl.mat4(0)
		proj[0, 0] = scale.x
		proj[1, 1] = scale.y
		proj[2, 2] = scale.z
		proj[0, 3] = offset.x
		proj[1, 3] = offset.y
		proj[2, 3] = offset.z
		proj[3, 3] = 1

		g_cascade_shadows_data.cascade_matrices[i] = coordinate_system_correction * proj * view

		render_views[i] = {
			view       = view,
			projection = coordinate_system_correction * proj,
		}

		render_pass_bindings_per_view[i] = create_cascade_render_pass_bindings(
			cascade_depth_image_refs[i],
			temp_arena.allocator,
		)

		cascade_near = cascade_far
	}

	render_instanced_mesh_job_run(
		cascade_render_task.desc.name,
		cascade_render_task_data.render_mesh_job,
		cascade_render_task_data.render_pass_ref,
		render_views,
		render_pass_bindings_per_view,
		cascade_render_task_data.material_pass_refs,
		cascade_render_task_data.material_pass_type,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
create_cascade_render_pass_bindings :: proc(
	p_cascade_image_ref: ImageRef,
	p_allocator: mem.Allocator,
) -> RenderPassBindings {

	render_pass_bindings := RenderPassBindings {
		image_outputs = make([]RenderPassImageOutput, 1, p_allocator),
	}

	render_pass_bindings.image_outputs[0] = RenderPassImageOutput {
		image_ref = p_cascade_image_ref,
		flags     = {.Clear},
	}

	return render_pass_bindings
}

//---------------------------------------------------------------------------//
