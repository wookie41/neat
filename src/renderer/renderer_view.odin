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
	jitter:     glsl.vec2,
}

//--------------------------------------------------------------------------//

RenderView :: struct {
	view:         glsl.mat4,
	projection:   glsl.mat4,
	position:     glsl.vec3,
	forward:      glsl.vec3,
	up:           glsl.vec3,
	near_plane:   f32,
	aspect_ratio: f32,
	jitter:       glsl.vec2,
}

//--------------------------------------------------------------------------//

RenderViews :: struct {
	current_view:  RenderView,
	previous_view: RenderView,
}
//--------------------------------------------------------------------------//

render_view_create_from_camera :: proc(
	p_render_camera: RenderCamera,
) -> (
	render_view: RenderView,
) {
	aspect_ratio :=
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y)

	render_view.view = glsl.mat4LookAt(
		p_render_camera.position,
		p_render_camera.position + p_render_camera.forward,
		p_render_camera.up,
	)
	render_view.projection = common.mat4PerspectiveInfiniteReverse(
		glsl.radians_f32(f32(p_render_camera.fov)),
		aspect_ratio,
		g_render_camera.near_plane,
	)
	render_view.projection =
		glsl.mat4Translate(glsl.vec3{p_render_camera.jitter.x, p_render_camera.jitter.y, 0}) *
		render_view.projection
	render_view.position = p_render_camera.position
	render_view.forward = p_render_camera.forward
	render_view.up = p_render_camera.up
	render_view.near_plane = p_render_camera.near_plane
	render_view.aspect_ratio = aspect_ratio
	render_view.jitter = p_render_camera.jitter

	return
}

//--------------------------------------------------------------------------//
