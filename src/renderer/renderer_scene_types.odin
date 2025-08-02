package renderer

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

DirectionalLight :: struct #packed {
	direction:              glsl.vec3,
	shadow_sampling_radius: f32,
	color:                  glsl.vec3,
	debug_draw_cascades:    u32,
	strength:               f32,
	padding:                glsl.uvec3,
}

//---------------------------------------------------------------------------//

@(private)
ShadowCascade :: struct #packed {
	light_matrix:  glsl.mat4,
	render_matrix: glsl.mat4,
	split:         f32,
	offset_scale:  glsl.vec2,
	_padding:      f32,
}

//---------------------------------------------------------------------------//
