package renderer

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

DirectionalLight :: struct #packed {
	direction:              glsl.vec3,
	shadow_sampling_radius: f32,
	color:                  glsl.vec3,
	debug_draw_cascades:    u32,
}

//---------------------------------------------------------------------------//
