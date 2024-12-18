package engine

//---------------------------------------------------------------------------//

import "core:math/linalg/glsl"
import "../common"

//---------------------------------------------------------------------------//

@(private)
Camera: struct {
	yaw:                  f32,
	pitch:                f32,
	position:             glsl.vec3,
	forward:              glsl.vec3,
	up:                   glsl.vec3,
	right:                glsl.vec3,
	fov:                  common.deg,
	speed:                f32,
	rotation_sensitivity: f32,
	near_plane:           f32,
	velocity:             glsl.vec3,
}

//---------------------------------------------------------------------------//

camera_init :: proc() {
	using Camera
	position = {50, 150, 500}
	speed = 0.5
	near_plane = 0.001
	fov = 45.0
	rotation_sensitivity = 0.25
	up = {0, 1, 0}
	right = {1, 0, 0}
	forward = {0, 0, -1}
	yaw = -90
	pitch = 0
}

//---------------------------------------------------------------------------//

camera_update :: proc(p_dt: f32) {
	using Camera
	position += (velocity * p_dt)
	velocity *= 0.85
}

//---------------------------------------------------------------------------//

camera_add_forward_velocity :: proc(p_multiplier: f32) {
	Camera.velocity += (Camera.forward * Camera.speed * p_multiplier)
}

//---------------------------------------------------------------------------//

camera_add_right_velocity :: proc(p_multiplier: f32) {
	Camera.velocity += (Camera.right * Camera.speed * p_multiplier)
}

//---------------------------------------------------------------------------//

camera_move_forward :: proc(p_dt: f32) {
	Camera.position += (Camera.forward * Camera.speed * p_dt)
}

//---------------------------------------------------------------------------//

camera_move_right :: proc(p_dt: f32) {
	Camera.position += (Camera.right * Camera.speed * p_dt)
}

//---------------------------------------------------------------------------//

camera_move_back :: proc(p_dt: f32) {
	Camera.position += (-Camera.forward * Camera.speed * p_dt)
}

//---------------------------------------------------------------------------//

camera_move_left :: proc(p_dt: f32) {
	Camera.position += (-Camera.right * Camera.speed * p_dt)
}

//---------------------------------------------------------------------------//

@(private = "file")
camera_update_vectors :: proc() {
	using Camera

	// calculate the new forward vector
	forward.x = glsl.cos(glsl.radians(yaw)) * glsl.cos(glsl.radians(pitch))
	forward.y = glsl.sin(glsl.radians(pitch))
	forward.z = glsl.sin(glsl.radians(yaw)) * glsl.cos(glsl.radians(pitch))
	forward = glsl.normalize(forward)

	// calculate the right and up vectors
	right = glsl.normalize(glsl.cross(forward, glsl.vec3{0, 1, 0}))
	up = glsl.normalize(glsl.cross(right, forward))
}

//---------------------------------------------------------------------------//

camera_add_rotation :: proc(p_yaw_offset: f32, p_pitch_offset: f32) {

	using Camera

	yaw_offset := p_yaw_offset * rotation_sensitivity
	pitch_offset := p_pitch_offset * rotation_sensitivity

	yaw += yaw_offset
	pitch += pitch_offset

	if pitch > 89.0 {
		pitch = 89.0
	} else if pitch < -89.0 {
		pitch = -89.0
	}

	camera_update_vectors()
}

//---------------------------------------------------------------------------//

camera_add_speed :: proc(p_speed_delta: f32) {
	using Camera
	speed += p_speed_delta
	speed = max(0.01, speed)
}

//---------------------------------------------------------------------------//
