package renderer

//--------------------------------------------------------------------------//

import "../common"

import "core:math/linalg/glsl"

//--------------------------------------------------------------------------//

RenderCamera :: struct {
	position:   glsl.vec3,
	forward:    glsl.vec3,
	up:         glsl.vec3,
	fov:        common.deg,
	near_plane: f32,
	far_plane:  f32,
}

//--------------------------------------------------------------------------//

RenderView :: struct {
	view:       glsl.mat4,
	projection: glsl.mat4,
	position:   glsl.vec3,
	forward:    glsl.vec3,
	up:    glsl.vec3,
	near_plane: f32,
}

//--------------------------------------------------------------------------//

render_camera_create_render_view :: proc(
	p_render_camera: RenderCamera,
) -> (
	render_view: RenderView,
) {

	render_view.view = glsl.mat4LookAt(
		p_render_camera.position,
		p_render_camera.position + p_render_camera.forward,
		p_render_camera.up,
	)
	render_view.projection = common.mat4PerspectiveInfiniteReverse(
		glsl.radians_f32(f32(p_render_camera.fov)),
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y),
		g_render_camera.near_plane,
	)
	render_view.position = p_render_camera.position
	render_view.forward = p_render_camera.forward
	render_view.up = p_render_camera.up
	render_view.near_plane = p_render_camera.near_plane

	return
}

//--------------------------------------------------------------------------//
