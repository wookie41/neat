package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:encoding/xml"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private)
MAX_SHADOW_CASCADES :: 6 // Keep in sync with resources.hlsli

@(private = "file")
CASCADE_SPLIT_LOG_FACTOR :: 0.90

//---------------------------------------------------------------------------//

@(private)
ShadowCascade :: struct #packed {
	light_matrix: glsl.mat4,
	split:        f32,
	_padding:     glsl.vec3,
}

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
CascadeMatrices :: struct {
	view: 		glsl.mat4,
	projection: glsl.mat4,
}

//---------------------------------------------------------------------------//

@(private="file")
INTERNAL : struct {
	cascade_matrices : [MAX_SHADOW_CASCADES]CascadeMatrices,
}

//--------------------------------------------------------------------------//

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
	max_shadows_distance := common.xml_get_f32_attribute(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"maxShadowsDistance",
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

	cascade_render_task_data.cascade_shadows_image_ref = find_image(cascades_image_name)

	render_mesh_job := render_instanced_mesh_job_create() or_return

	cascade_render_task.data_ptr = rawptr(cascade_render_task_data)
	cascade_render_task_data.render_mesh_job = render_mesh_job
	cascade_render_task_data.num_cascades = num_cascades
	cascade_render_task_data.max_shadows_distance = max_shadows_distance

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

	// Calculation of the cascade planes based on
	// https://developer.download.nvidia.com/SDK/10.5/opengl/src/cascaded_shadow_maps/doc/cascaded_shadow_maps.pdf

	cascade_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	cascade_render_task_data := (^CascadeShadowsRenderTaskData)(cascade_render_task.data_ptr)

	using cascade_render_task_data

	camera_near := g_render_camera.near_plane

	g_per_frame_data.num_shadow_cascades = num_cascades

	// First, calculate the far splits
	for i in 0 ..< num_cascades {

		g_per_frame_data.shadow_cascades[i].split = glsl.lerp(
			camera_near + (f32(i + 1) / f32(num_cascades)) * (max_shadows_distance - camera_near),
			camera_near *
			glsl.pow(max_shadows_distance / camera_near, f32(i + 1) / f32(num_cascades)),
			CASCADE_SPLIT_LOG_FACTOR,
		)

		// linear
		// g_per_frame_data.shadow_cascades[i].split = camera_near + ((max_shadows_distance - camera_near) * f32(i + 1) / f32(num_cascades))
	}

	camera_aspect_ratio :=
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y)

	// Map Z component from [-1; 1] to [0; 1]
	ndc_z_correction := glsl.mat4 {
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, -0.5, 0.0,
		0.0, 0.0, 0.5, 1.0,
	}
	ndc_z_correction = glsl.transpose(ndc_z_correction)

	// Map NDC X and Y coordinates from [-1; 1] to [0;1] for shadow map sampling
	texture_space_conversion := glsl.mat4 {
		0.5, 0.0, 0.0, 0.0,
		0.0, -0.5, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		0.5, 0.5, 0.0, 1.0,
	}
	texture_space_conversion = glsl.transpose(texture_space_conversion)

	forward := -g_per_frame_data.sun.direction
	up := glsl.vec3{0.0, -1.0, 0.0} if glsl.abs(forward.y) < 0.9999 else glsl.vec3{0.0, 0.0, -1.0}
	cascade_near := g_render_camera.near_plane

	for i in 0 ..< num_cascades {

		cascade_far := g_per_frame_data.shadow_cascades[i].split

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
		view := glsl.mat4LookAt(frustum_center - forward, frustum_center, up)

		// Find the min and max point (bounding box) of this part of the frustum,
		// transform it to the POV of the light  space and based on the build the projection matrix. 
		min_p := glsl.vec3(max(f32))
		max_p := glsl.vec3(min(f32))

		for i in 0 ..< len(frustum_points) {
			p: glsl.vec3 =
				(view * glsl.vec4{frustum_points[i].x, frustum_points[i].y, frustum_points[i].z, 1}).xyz
			min_p = glsl.min(min_p, p)
			max_p = glsl.max(max_p, p)
		}

		scale := glsl.vec3(2) / (max_p - min_p)
		offset := -0.5 * (max_p + min_p) * scale

		proj := glsl.mat4 {
			scale.x, 0.0, 0.0, 0.0,
			0.0, scale.y, 0.0, 0.0,
			0.0, 0.0, scale.z, 0.0,
			offset.x, offset.y, offset.z, 1.0,
		}
		proj = glsl.transpose(proj)

		// This is used to sample the shadow maps
		g_per_frame_data.shadow_cascades[i].light_matrix =
			texture_space_conversion * ndc_z_correction * proj * view

		// These are used during rendering
		INTERNAL.cascade_matrices[i].view = view
		INTERNAL.cascade_matrices[i].projection = ndc_z_correction * proj
		
		cascade_near = cascade_far
	}
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

	for i in 0 ..< num_cascades {

		render_views[i] = {
			view       = INTERNAL.cascade_matrices[i].view,
			projection = INTERNAL.cascade_matrices[i].projection,
		}

		render_pass_bindings_per_view[i] = create_cascade_render_pass_bindings(
			cascade_shadows_image_ref,
			u32(i),
			temp_arena.allocator,
		)
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
