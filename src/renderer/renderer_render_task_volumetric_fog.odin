package renderer

//---------------------------------------------------------------------------//

// Tak responsible for computing the volumetric fog (constant, height and box)
// that is then used when shading. Outputs a 3D texture.

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"

import imgui "../third_party/odin-imgui"

//---------------------------------------------------------------------------//

@(private = "file")
VOLUMETRIC_FOG_IMAGE_RESOLUTION :: glsl.uvec3{128, 128, 128}

@(private = "file")
VOLUMETRIC_FOG_DISPATCH_SIZE :: glsl.uvec3{8, 8, 1}

//---------------------------------------------------------------------------//

@(private = "file")
VolumetricFogRenderTaskData :: struct {
	inject_fog_job:                    GenericComputeJob,
	inject_fog_bindings:               []Binding,
	light_scattering_job:              GenericComputeJob,
	light_scattering_bindings:         []Binding,
	integrate_light_job:               GenericComputeJob,
	integrate_light_bindings:          []Binding,
	spatial_filter_job:                GenericComputeJob,
	spatial_filter_bindings:           []Binding,
	temporal_filter_job:               GenericComputeJob,
	temporal_filter_bindings:          []Binding,
	volumetric_fog_image_ref:          ImageRef,
	previous_volumetric_fog_image_ref: ImageRef,
	working_image_refs:                [2]ImageRef,
	uniform_data:                      VolumetricFogUniformData,
}

//---------------------------------------------------------------------------//

@(private = "file")
VolumetricFogUniformData :: struct #packed {
	froxel_dimensions:                    glsl.uvec3,
	temporal_reprojection_jitter_scale:   f32,
	noise_type:                           i32,
	noise_scale:                          f32,
	spatial_filter_enabled:               u32,
	temporal_filter_enabled:              u32,
	height_fog_falloff:                   f32,
	scattering_factor:                    f32,
	volumetric_noise_position_multiplier: f32,
	volumetric_noise_speed_multiplier:    f32,
	constant_fog_density:                 f32,
	constant_fog_color:                   glsl.vec3,
	height_fog_density:                   f32,
	height_fog_color:                     glsl.vec3,
	box_fog_density:                      f32,
	box_fog_position:                     glsl.vec3,
	box_fog_size:                         glsl.vec3,
	_padding1:                            u32,
	box_fog_color:                        glsl.vec3,
	_padding2:                            u32,
	phase_anisotrophy_01:                 f32,
	phase_function_type:                  i32,
	volumetric_fog_opacity_aa_enabled:    u32,
	temporal_reprojection_percentage:     f32,
	volumetric_noise_direction:           glsl.vec3,
	_padding3:                            u32,
	view_proj:                            glsl.mat4x4,
	inv_view_proj:                        glsl.mat4x4,
	previous_view_proj:                   glsl.mat4x4,
}

//---------------------------------------------------------------------------//

volumetric_fog_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
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
	// Parse task config
	inject_data_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"injectDataShader",
	) or_return

	scatter_light_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"scatterLightShader",
	) or_return

	integrate_light_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"integrateLightShader",
	) or_return

	spatial_filter_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"spatialFilterShader",
	) or_return

	temporal_filter_shader_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"temporalFilterShader",
	) or_return

	volumetric_fog_image_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"volumetricFogImage",
	) or_return

	inject_data_shader_ref := shader_find_by_name(inject_data_shader_name)
	if inject_data_shader_ref == InvalidShaderRef {
		log.error("Invalid InjectData shader\n")
		return false
	}

	scatter_light_shader_ref := shader_find_by_name(scatter_light_shader_name)
	if scatter_light_shader_ref == InvalidShaderRef {
		log.error("Invalid ScatterLight shader\n")
		return false
	}

	integrate_light_shader_ref := shader_find_by_name(integrate_light_shader_name)
	if integrate_light_shader_ref == InvalidShaderRef {
		log.error("Invalid IntegrateLight shader\n")
		return false
	}

	spatial_filter_shader_ref := shader_find_by_name(spatial_filter_shader_name)
	if spatial_filter_shader_ref == InvalidShaderRef {
		log.error("Invalid SpatialFilter shader\n")
		return false
	}

	temporal_filter_shader_ref := shader_find_by_name(temporal_filter_shader_name)
	if temporal_filter_shader_ref == InvalidShaderRef {
		log.error("Invalid TemporalFilter shader\n")
		return false
	}

	// Create all of the needed images
	volumetric_fog_image_ref := image_allocate(common.create_name(volumetric_fog_image_name))
	volumetric_fog_image := &g_resources.images[image_get_idx(volumetric_fog_image_ref)]
	volumetric_fog_image.desc.array_size = 1
	volumetric_fog_image.desc.dimensions = VOLUMETRIC_FOG_IMAGE_RESOLUTION
	volumetric_fog_image.desc.flags = {.Storage, .Sampled}
	volumetric_fog_image.desc.format = .RGBA16SFloat
	volumetric_fog_image.desc.mip_count = 1
	volumetric_fog_image.desc.type = .ThreeDimensional
	image_create(volumetric_fog_image_ref) or_return

	previous_volumetric_fog_image_ref := image_allocate(
		common.create_name("PreviousVolumetricFog"),
	)
	previous_volumetric_fog_image := &g_resources.images[image_get_idx(previous_volumetric_fog_image_ref)]
	previous_volumetric_fog_image.desc = volumetric_fog_image.desc
	previous_volumetric_fog_image.desc.name = common.create_name("PreviousVolumetricFog")
	image_create(previous_volumetric_fog_image_ref) or_return

	working_image1_ref := image_allocate(common.create_name("VolumetricFogWorking1"))
	working_image1 := &g_resources.images[image_get_idx(working_image1_ref)]
	working_image1.desc = volumetric_fog_image.desc
	working_image1.desc.name = common.create_name("VolumetricFogWorking1")
	image_create(working_image1_ref) or_return

	working_image2_ref := image_allocate(common.create_name("VolumetricFogWorking2"))
	working_image2 := &g_resources.images[image_get_idx(working_image2_ref)]
	working_image2.desc = working_image1.desc
	working_image2.desc.name = common.create_name("VolumetricFogWorking2")
	image_create(working_image2_ref) or_return

	render_task_data := new(VolumetricFogRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)

	render_task_data.volumetric_fog_image_ref = volumetric_fog_image_ref
	render_task_data.previous_volumetric_fog_image_ref = previous_volumetric_fog_image_ref
	render_task_data.working_image_refs[0] = working_image1_ref
	render_task_data.working_image_refs[1] = working_image2_ref

	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Create inject data job
	{
		bindings := render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(VolumetricFogUniformData)},
			"InjectDataBindings",
		) or_return

		render_task_data.inject_fog_job = generic_compute_job_create(
			common.create_name(inject_data_shader_name),
			inject_data_shader_ref,
			bindings,
		) or_return

		render_task_data.inject_fog_bindings = bindings
	}

	// Create light scattering job
	{
		bindings := render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(VolumetricFogUniformData)},
			"LightScatteringBindings",
		) or_return

		render_task_data.light_scattering_job = generic_compute_job_create(
			common.create_name(scatter_light_shader_name),
			scatter_light_shader_ref,
			bindings,
		) or_return

		render_task_data.light_scattering_bindings = bindings
	}

	// Create light integration job
	{
		bindings := render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(VolumetricFogUniformData)},
			"IntegrateLightBindings",
		) or_return

		render_task_data.integrate_light_job = generic_compute_job_create(
			common.create_name(integrate_light_shader_name),
			integrate_light_shader_ref,
			bindings,
		) or_return

		render_task_data.integrate_light_bindings = bindings

	}
	// Create spatial filter job
	{
		bindings := render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(VolumetricFogUniformData)},
			"SpatialFilterBindings",
		) or_return

		render_task_data.spatial_filter_job = generic_compute_job_create(
			common.create_name(spatial_filter_shader_name),
			spatial_filter_shader_ref,
			bindings,
		) or_return

		render_task_data.spatial_filter_bindings = bindings
	}

	// Create temporal filter job
	{
		bindings := render_task_config_parse_bindings(
			p_render_task_config,
			true,
			{size_of(VolumetricFogUniformData)},
			"TemporalFilterBindings",
		) or_return

		render_task_data.temporal_filter_job = generic_compute_job_create(
			common.create_name(temporal_filter_shader_name),
			temporal_filter_shader_ref,
			bindings,
		) or_return

		render_task_data.temporal_filter_bindings = bindings
	}

	render_task_data.uniform_data = VolumetricFogUniformData {
		froxel_dimensions                    = VOLUMETRIC_FOG_IMAGE_RESOLUTION,
		temporal_reprojection_jitter_scale   = 0.05,
		noise_type                           = 0,
		noise_scale                          = 0.1,
		spatial_filter_enabled               = 1,
		temporal_filter_enabled              = 1,
		volumetric_noise_position_multiplier = 0.1,
		volumetric_noise_speed_multiplier    = 0.001,
		volumetric_noise_direction           = {1, 0, 0},
		constant_fog_density                 = 0.1,
		constant_fog_color                   = glsl.vec3{0.5, 0.5, 0.5},
		height_fog_density                   = 0,
		height_fog_color                     = glsl.vec3{0, 0.5, 0},
		height_fog_falloff                   = 1,
		scattering_factor                    = 0.1,
		box_fog_density                      = 0.0,
		box_fog_position                     = glsl.vec3{0, 0, 0},
		box_fog_size                         = glsl.vec3{5, 5, 5},
		box_fog_color                        = glsl.vec3{0, 0, 1},
		phase_anisotrophy_01                 = 0.2,
		phase_function_type                  = 0,
		volumetric_fog_opacity_aa_enabled    = 1,
		temporal_reprojection_percentage     = 0.05,
	}

	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task.data_ptr = rawptr(render_task_data)
	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^VolumetricFogRenderTaskData)(render_task.data_ptr)

	generic_compute_job_destroy(render_task_data.inject_fog_job)
	generic_compute_job_destroy(render_task_data.light_scattering_job)
	generic_compute_job_destroy(render_task_data.integrate_light_job)
	generic_compute_job_destroy(render_task_data.spatial_filter_job)
	generic_compute_job_destroy(render_task_data.temporal_filter_job)

	delete(render_task_data.inject_fog_bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(render_task_data.light_scattering_bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(render_task_data.integrate_light_bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(render_task_data.spatial_filter_bindings, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(render_task_data.temporal_filter_bindings, G_RENDERER_ALLOCATORS.resource_allocator)

	free(render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc(p_render_task_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^VolumetricFogRenderTaskData)(render_task.data_ptr)

	g_per_frame_data.volumetric_fog_dimensions = VOLUMETRIC_FOG_IMAGE_RESOLUTION
	g_per_frame_data.volumetric_fog_opacity_aa_enabled =
		render_task_data.uniform_data.volumetric_fog_opacity_aa_enabled
}

//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(p_render_task_ref: RenderTaskRef, pdt: f32) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^VolumetricFogRenderTaskData)(render_task.data_ptr)

	if get_frame_id() > 0 {
		image_copy_content(
			get_frame_cmd_buffer_ref(),
			render_task_data.volumetric_fog_image_ref,
			render_task_data.previous_volumetric_fog_image_ref,
		)
	}

	gpu_debug_region_begin(get_frame_cmd_buffer_ref(), render_task.desc.name)
	defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

	render_views := RenderViews {
		current_view  = render_view_create_from_camera(g_render_camera),
		previous_view = render_view_create_from_camera(g_previous_render_camera),
	}

	global_uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		uniform_buffer_create_view_data(render_views),
	}

	render_task_data.uniform_data.previous_view_proj = render_task_data.uniform_data.view_proj
	render_task_data.uniform_data.view_proj =
		glsl.mat4Perspective(
			g_render_camera.fov,
			render_views.current_view.aspect_ratio,
			render_views.current_view.near_plane,
			g_per_frame_data.volumetric_fog_far,
		) *
		render_views.current_view.view
	render_task_data.uniform_data.inv_view_proj = glsl.inverse(
		render_task_data.uniform_data.view_proj,
	)

	job_uniform_data_offsets := []u32 {
		uniform_buffer_create_transient_buffer(&render_task_data.uniform_data),
	}

	transition_binding_resources(render_task_data.inject_fog_bindings, .Compute)
	transition_binding_resources(render_task_data.light_scattering_bindings, .Compute)

	// Inject fog data
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Inject fog data")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		compute_command_dispatch(
			render_task_data.inject_fog_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			VOLUMETRIC_FOG_IMAGE_RESOLUTION / VOLUMETRIC_FOG_DISPATCH_SIZE,
			{job_uniform_data_offsets, global_uniform_offsets, nil, nil},
			nil,
		)
	}

	// Calculate light scattering
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Calculate light scattering")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		compute_command_dispatch(
			render_task_data.light_scattering_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			VOLUMETRIC_FOG_IMAGE_RESOLUTION / VOLUMETRIC_FOG_DISPATCH_SIZE,
			{job_uniform_data_offsets, global_uniform_offsets, nil, nil},
			nil,
		)
	}

	transition_binding_resources(render_task_data.integrate_light_bindings, .Compute)

	// Integrate light
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Integrate light")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		compute_command_dispatch(
			render_task_data.integrate_light_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			glsl.uvec3 {
				VOLUMETRIC_FOG_IMAGE_RESOLUTION.x / VOLUMETRIC_FOG_DISPATCH_SIZE.x,
				VOLUMETRIC_FOG_IMAGE_RESOLUTION.y / VOLUMETRIC_FOG_DISPATCH_SIZE.y,
				1,
			},
			{job_uniform_data_offsets, global_uniform_offsets, nil, nil},
			nil,
		)
	}

	transition_binding_resources(render_task_data.spatial_filter_bindings, .Compute)

	// Spatial filter
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Spatial filter")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		compute_command_dispatch(
			render_task_data.spatial_filter_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			VOLUMETRIC_FOG_IMAGE_RESOLUTION / VOLUMETRIC_FOG_DISPATCH_SIZE,
			{job_uniform_data_offsets, global_uniform_offsets, nil, nil},
			nil,
		)
	}

	transition_binding_resources(render_task_data.temporal_filter_bindings, .Compute)

	// Temporal filter
	{
		gpu_debug_region_begin(get_frame_cmd_buffer_ref(), "Temporal filter")
		defer gpu_debug_region_end(get_frame_cmd_buffer_ref())

		compute_command_dispatch(
			render_task_data.temporal_filter_job.compute_command_ref,
			get_frame_cmd_buffer_ref(),
			VOLUMETRIC_FOG_IMAGE_RESOLUTION / VOLUMETRIC_FOG_DISPATCH_SIZE,
			{job_uniform_data_offsets, global_uniform_offsets, nil, nil},
			nil,
		)
	}
}

//---------------------------------------------------------------------------//


@(private = "file")
draw_debug_ui :: proc(p_render_task_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	render_task_data := (^VolumetricFogRenderTaskData)(render_task.data_ptr)

	if (imgui.CollapsingHeader("Volumetric fog", {})) {
		imgui.SliderFloat(
			"Far plane",
			&g_per_frame_data.volumetric_fog_far,
			g_render_camera.near_plane,
			200,
		)

		imgui.Checkbox(
			"Spatial filter enabled",
			(^bool)(&render_task_data.uniform_data.spatial_filter_enabled),
		)
		imgui.Checkbox(
			"Temporal filter enabled",
			(^bool)(&render_task_data.uniform_data.temporal_filter_enabled),
		)

		imgui.Checkbox(
			"Opacity AA enabled",
			(^bool)(&render_task_data.uniform_data.volumetric_fog_opacity_aa_enabled),
		)

		imgui.SliderFloat(
			"Temporal reprojection jitter scale",
			&render_task_data.uniform_data.temporal_reprojection_jitter_scale,
			0,
			0.2,
		)

		imgui.SliderInt("Noise type", &render_task_data.uniform_data.noise_type, 0, 2)
		imgui.SliderFloat("Noise scale", &render_task_data.uniform_data.noise_scale, 0, 1)

		imgui.SliderFloat(
			"Scattering factor",
			&render_task_data.uniform_data.scattering_factor,
			0,
			1,
		)

		imgui.SliderFloat(
			"Phase anisotrophy",
			&render_task_data.uniform_data.phase_anisotrophy_01,
			0,
			1,
		)
		imgui.SliderInt("Phase function type", &render_task_data.uniform_data.noise_type, 0, 3)

		imgui.SliderFloat(
			"Temporal reprojection percentage",
			&render_task_data.uniform_data.temporal_reprojection_percentage,
			0,
			1,
		)

		imgui.DragFloatEx(
			"Volumetric noise scale",
			&render_task_data.uniform_data.volumetric_noise_position_multiplier,
			0.1,
			0,
			1,
			nil,
			{},
		)

		imgui.DragFloatEx(
			"Volumetric noise speed",
			&render_task_data.uniform_data.volumetric_noise_speed_multiplier,
			0.0001,
			0.0001,
			0.001,
			nil,
			{},
		)

		imgui.SliderFloat3(
			"Volumetric noise direction",
			&render_task_data.uniform_data.volumetric_noise_direction,
			-1,
			1,
		)

		imgui.Separator()

		imgui.SliderFloat(
			"Constant fog density",
			&render_task_data.uniform_data.constant_fog_density,
			0,
			3,
		)
		imgui.ColorEdit3(
			"Constant fog color",
			&render_task_data.uniform_data.constant_fog_color,
			{},
		)

		imgui.Separator()

		imgui.SliderFloat(
			"Height density",
			&render_task_data.uniform_data.height_fog_density,
			0,
			3,
		)
		imgui.ColorEdit3("Height fog color", &render_task_data.uniform_data.height_fog_color, {})
		imgui.SliderFloat(
			"Height fog fallof",
			&render_task_data.uniform_data.height_fog_falloff,
			0,
			1,
		)

		imgui.Separator()

		imgui.SliderFloat("Box fog density", &render_task_data.uniform_data.box_fog_density, 0, 3)
		imgui.SliderFloat3(
			"Box position",
			&render_task_data.uniform_data.box_fog_position,
			-10,
			10,
		)
		imgui.SliderFloat3("Box fog size", &render_task_data.uniform_data.box_fog_size, 0, 5)
		imgui.ColorEdit3("Box fog color", (&render_task_data.uniform_data.box_fog_color), {})

		imgui.Separator()
	}
}


//---------------------------------------------------------------------------//
