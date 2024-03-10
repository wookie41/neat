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
	view: glsl.mat4x4,
	proj: glsl.mat4x4,
}

//---------------------------------------------------------------------------//

@(private)
g_uniform_buffers: struct {
	per_instance_buffer_ref: BufferRef,
	per_view_buffer_ref:     BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_management_init :: proc() {

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
	update_per_view_uniform_buffer(p_dt)
}


//---------------------------------------------------------------------------//

@(private = "file")
update_per_view_uniform_buffer :: proc(p_dt: f32) {

	g_per_view_uniform_buffer_data.view = glsl.mat4LookAt(
		g_render_camera.position,
		g_render_camera.position + g_render_camera.forward,
		g_render_camera.up,
	)
	g_per_view_uniform_buffer_data.proj = glsl.mat4Perspective(
		glsl.radians_f32(g_render_camera.fov_degrees),
		f32(G_RENDERER.config.render_resolution.x) / f32(G_RENDERER.config.render_resolution.y),
		g_render_camera.near_plane,
		g_render_camera.far_plane,
	)

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

@(private)
uniform_buffer_management_get_per_frame_offset :: proc() -> u32 {
	return 0
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

	buffer_offset := get_frame_idx() * G_PER_INSTANCE_UNIFORM_BUFFER_SIZE + INTERNAL.current_instance_buffer_offset
	INTERNAL.current_instance_buffer_offset = buffer_offset

	per_instance_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.per_instance_buffer_ref)]
	
	mem.copy(mem.ptr_offset(per_instance_buffer.mapped_ptr, buffer_offset), p_data, int(p_size))

	return buffer_offset
}

//---------------------------------------------------------------------------//
