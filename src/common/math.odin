package common

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"


//---------------------------------------------------------------------------//
deg :: f32
rad :: f32

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

//---------------------------------------------------------------------------//

// http://www.lighthouse3d.com/tutorials/view-frustum-culling/geometric-approach-extracting-the-planes/
compute_frustum_points :: proc(
	p_near, p_far, p_aspect_ratio: f32,
	p_fov: rad,
	p_position, p_forward, p_up: glsl.vec3,
) -> (
	p_frustum_points: [8]glsl.vec3, p_frustum_center: glsl.vec3,
) {

	right := glsl.normalize(glsl.cross(p_forward, p_up))

	near_plane_center := p_position.xyz + p_forward.xyz * p_near
	far_plane_center := p_position.xyz + p_forward.xyz * p_far

	tan_fov_half := glsl.tan(p_fov * 0.5)

	height_near := tan_fov_half * p_near
	height_far := tan_fov_half * p_far

	width_near := height_near * p_aspect_ratio
	width_far := height_far * p_aspect_ratio

	p_frustum_points[0] = far_plane_center + p_up.xyz * height_far + right.xyz * width_far
	p_frustum_points[1] = far_plane_center + p_up.xyz * height_far - right.xyz * width_far
	p_frustum_points[2] = far_plane_center - p_up.xyz * height_far + right.xyz * width_far
	p_frustum_points[3] = far_plane_center - p_up.xyz * height_far - right.xyz * width_far

	p_frustum_points[4] = near_plane_center + p_up * height_near + right * width_near
	p_frustum_points[5] = near_plane_center + p_up * height_near - right * width_near
	p_frustum_points[6] = near_plane_center - p_up * height_near + right * width_near
	p_frustum_points[7] = near_plane_center - p_up * height_near - right * width_near

	p_frustum_center = glsl.vec3(0)
	for p in p_frustum_points {
		p_frustum_center += p
	}
	p_frustum_center /= 8

	return
}

//---------------------------------------------------------------------------//
