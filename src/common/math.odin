package common

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

@(require_results)
mat4PerspectiveInfiniteReverse :: proc "c" (fovy, aspect, near: f32) -> (m: glsl.mat4) {
	tan_half_fovy := glsl.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect*tan_half_fovy)
	m[1, 1] = 1 / (tan_half_fovy)
	m[3, 2] = -1
	m[2, 3] = near
	return
}