package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	current_instance_buffer_offset: u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_PER_INSTANCE_UNIFORM_BUFFER_SIZE :: common.KILOBYTE * 8

//---------------------------------------------------------------------------//

@(private)
g_per_view_uniform_buffer_data: struct #packed {
	view:          glsl.mat4x4,
	proj:          glsl.mat4x4,
	inv_view_proj: glsl.mat4x4,
	camera_pos_ws: glsl.vec3,
	_padding:      [52]byte,
}

//---------------------------------------------------------------------------//

@(private)
g_per_frame_uniform_buffer_data: struct #packed {
	sun:      DirectionalLight,
	_padding: [32]byte,
}

//---------------------------------------------------------------------------//

@(private)
g_uniform_buffers: struct {
	per_instance_buffer_ref: BufferRef,
	per_view_buffer_ref:     BufferRef,
	per_frame_buffer_ref:    BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_init :: proc() {

	// Create the per frame uniform buffer
	{
		g_uniform_buffers.per_frame_buffer_ref = allocate_buffer_ref(
			common.create_name("PerFrame"),
		)
		per_frame_uniform_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_frame_buffer_ref)]

		per_frame_uniform_buffer.desc.flags = {.HostWrite, .Mapped}
		per_frame_uniform_buffer.desc.size =
			size_of(g_per_frame_uniform_buffer_data) * G_RENDERER.num_frames_in_flight
		per_frame_uniform_buffer.desc.usage = {.DynamicUniformBuffer}

		create_buffer(g_uniform_buffers.per_frame_buffer_ref)
	}

	// Create the per view uniform buffer
	{
		g_uniform_buffers.per_view_buffer_ref = allocate_buffer_ref(common.create_name("PerView"))
		per_view_uniform_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_view_buffer_ref)]

		per_view_uniform_buffer.desc.flags = {.HostWrite, .Mapped}
		per_view_uniform_buffer.desc.size =
			size_of(g_per_view_uniform_buffer_data) * G_RENDERER.num_frames_in_flight
		per_view_uniform_buffer.desc.usage = {.DynamicUniformBuffer}

		create_buffer(g_uniform_buffers.per_view_buffer_ref)
	}

	// Create the instance view uniform buffer
	{
		g_uniform_buffers.per_instance_buffer_ref = allocate_buffer_ref(
			common.create_name("PerInstance"),
		)
		per_instance_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_instance_buffer_ref)]

		per_instance_buffer.desc.flags = {.HostWrite, .Mapped}
		per_instance_buffer.desc.size =
			G_PER_INSTANCE_UNIFORM_BUFFER_SIZE * G_RENDERER.num_frames_in_flight
		per_instance_buffer.desc.usage = {.DynamicUniformBuffer}

		create_buffer(g_uniform_buffers.per_instance_buffer_ref)
	}
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_update :: proc(p_dt: f32) {
	// Reset the instance buffer
	INTERNAL.current_instance_buffer_offset = 0
	update_per_frame_uniform_buffer(p_dt)
	update_per_view_uniform_buffer(p_dt)
}


//---------------------------------------------------------------------------//

@(private = "file")
update_per_view_uniform_buffer :: proc(p_dt: f32) {

	view_matrix := glsl.mat4LookAt(
		g_render_camera.position,
		g_render_camera.position + g_render_camera.forward,
		g_render_camera.up,
	)

	projection_matrix := glsl.mat4Perspective(
		glsl.radians_f32(g_render_camera.fov_degrees),
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y),
		g_render_camera.near_plane,
		g_render_camera.far_plane,
	)

	g_per_view_uniform_buffer_data.view = view_matrix
	g_per_view_uniform_buffer_data.proj = projection_matrix
	g_per_view_uniform_buffer_data.inv_view_proj = glsl.inverse(view_matrix * projection_matrix)
	g_per_view_uniform_buffer_data.camera_pos_ws = g_render_camera.position

	uniform_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_view_buffer_ref)]
	mem.copy(
		mem.ptr_offset(
			uniform_buffer.mapped_ptr,
			size_of(g_per_view_uniform_buffer_data) * get_frame_idx(),
		),
		&g_per_view_uniform_buffer_data,
		size_of(g_per_view_uniform_buffer_data),
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
update_per_frame_uniform_buffer :: proc(p_dt: f32) {
	g_per_frame_uniform_buffer_data.sun.direction = glsl.normalize(glsl.vec3{0, -1, 0})
	g_per_frame_uniform_buffer_data.sun.color = glsl.vec3(1)

	uniform_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_frame_buffer_ref)]
	mem.copy(
		mem.ptr_offset(
			uniform_buffer.mapped_ptr,
			size_of(g_per_frame_uniform_buffer_data) * get_frame_idx(),
		),
		&g_per_frame_uniform_buffer_data,
		size_of(g_per_frame_uniform_buffer_data),
	)
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_get_per_frame_offset :: proc() -> u32 {
	return size_of(g_per_frame_uniform_buffer_data) * get_frame_idx()
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_get_per_view_offset :: proc() -> u32 {
	return size_of(g_per_view_uniform_buffer_data) * get_frame_idx()
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_request_per_instance_data :: proc(p_data: rawptr, p_size: u32) -> u32 {

	if INTERNAL.current_instance_buffer_offset + p_size >= G_PER_INSTANCE_UNIFORM_BUFFER_SIZE {
		return 0
	}

	buffer_offset :=
		get_frame_idx() * G_PER_INSTANCE_UNIFORM_BUFFER_SIZE +
		INTERNAL.current_instance_buffer_offset
	INTERNAL.current_instance_buffer_offset = buffer_offset

	per_instance_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_instance_buffer_ref)]

	mem.copy(mem.ptr_offset(per_instance_buffer.mapped_ptr, buffer_offset), p_data, int(p_size))

	return buffer_offset
}

//---------------------------------------------------------------------------//
