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
	m[0, 0] = 1 / (aspect * tan_half_fovy)
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
	p_frustum_points: [8]glsl.vec3,
	p_frustum_center: glsl.vec3,
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

// Creates a halton sequence of values between 0 and 1.
// https://en.wikipedia.org/wiki/Halton_sequence
// Used for jittering based on a constant set of 2D points.

halton :: proc(i: i32, b: i32) -> f32 {
	f: f32 = 1.0
	r: f32 = 0.0
	ii := i
	for (ii > 0) {
		f = f / f32(b)
		r = r + f * f32(ii % b)
		ii = ii / b
	}
	return r
}

//---------------------------------------------------------------------------//

pack_rgba_color :: proc(color: glsl.vec4) -> u32 {
	return(
		u32(color.r * 255) |
		(u32(color.g * 255) << 8) |
		(u32(color.b * 255) << 16) |
		((u32(color.a * 255) << 24)) \
	)
}

//---------------------------------------------------------------------------//

// http://www.pbr-book.org/3ed-2018/Sampling_and_Reconstruction/The_Halton_Sampler.html
reverse32Bit :: proc(x: u32) -> u32 {
	out: u32 = (x << 16) | (x >> 16) //swap adjacent 16 bits
	out = ((out & 0x00ff00ff) << 8) | ((out & 0xff00ff00) >> 8) //swap adjacent 8 bits
	out = ((out & 0x0f0f0f0f) << 4) | ((out & 0xf0f0f0f0) >> 4) //swap adjacent 4 bits
	out = ((out & 0x33333333) << 2) | ((out & 0xcccccccc) >> 2) //swap adjacent 2 bits
	out = ((out & 0x55555555) << 1) | ((out & 0xaaaaaaaa) >> 1) //swap adjacent 1 bits
	return out
}

//---------------------------------------------------------------------------//

// http://www.pbr-book.org/3ed-2018/Sampling_and_Reconstruction/The_Halton_Sampler.html
radical_inverse_base2 :: proc(x: u32) -> f32 {
	return f32(reverse32Bit(x)) * f32(2.3283064365386963e-10)
}

//---------------------------------------------------------------------------//

// http://www.pbr-book.org/3ed-2018/Sampling_and_Reconstruction/The_Halton_Sampler.html
radical_inverse_base3 :: proc(x: u32) -> f32 {
	base: u32 = 3
	inverse_base := 1.0 / f32(base)
	reversed_digits : u32= 0
	current := x //example: starting at 10
	//we go from largest to smallest digit, until current reaches 0
	inverse_base_power_n: f32 = 1
	for (current > 0) {
		next: u32 = current / base //example: 10 / base = 3
		//digits go from 0 to base-1
		//for example binary hase base 2 and has digits 0 and 1
		digit: u32 = current - next * base //example: 10 - 3 * 3 = 10 - 9 = 1
		reversed_digits *= base //'lifting' current digits to the next base
		//example: take 101 base 10 and go left to right
		//the first 1 has to be 'lifted' twice
		//101 = 1 * 100 + 1 * 10 + 1 * 1
		reversed_digits += digit //adding current digit
		inverse_base_power_n *= inverse_base //incrementally building 1 / base^n
		//this is simply done by multiplying 1 / base together n times
		current = next
	}
	return f32(reversed_digits) * inverse_base_power_n //we multiply only once at the end with the inverse base
	//by the previous 'lifting' this provides the correct weight per digit
}

//---------------------------------------------------------------------------//

// http://www.pbr-book.org/3ed-2018/Sampling_and_Reconstruction/The_Halton_Sampler.html
hammersley2D :: proc(index: u32) -> glsl.vec2 {
	return glsl.vec2{radical_inverse_base2(index), radical_inverse_base3(index)}
}


//---------------------------------------------------------------------------//
