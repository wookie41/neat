package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	current_transient_buffer_offset: u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
TRANSIENT_UNIFORM_BUFFER_SIZE :: common.KILOBYTE * 8

//---------------------------------------------------------------------------//

@(private)
PerViewData :: struct #packed {
	view:          glsl.mat4x4,
	proj:          glsl.mat4x4,
	inv_view_proj: glsl.mat4x4,
	camera_pos_ws: glsl.vec3,
	_padding:      f32,
}

//---------------------------------------------------------------------------//

@(private)
g_per_frame_data: struct #packed {
	sun: DirectionalLight,
}

//---------------------------------------------------------------------------//

@(private)
g_uniform_buffers: struct {
	transient_buffer:  DynamicUniformBuffer,
	frame_data_offset: u32,
}

//---------------------------------------------------------------------------//

DynamicUniformBuffer :: struct {
	buffer_ref:   BufferRef,
	aligned_size: u32,
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_init :: proc() {
	g_uniform_buffers.transient_buffer = uniform_buffer_create_dynamic(
		common.create_name("TransientBuffer"),
		TRANSIENT_UNIFORM_BUFFER_SIZE,
	)
}

//---------------------------------------------------------------------------//

uniform_buffer_create_dynamic :: proc {
	uniform_buffer_create_dynamic_by_type,
	uniform_buffer_create_dynamic_by_size,
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffers_update :: proc(p_dt: f32) {
	// Reset the transient buffer
	INTERNAL.current_transient_buffer_offset = 0

	update_per_frame_data(p_dt)
}

//---------------------------------------------------------------------------//


// Creates a transient buffer that can be used to send constant data to a render task
// Transient buffer are valid only within the frame boundary

uniform_buffer_create_transient_buffer :: proc(p_data: ^$T) -> u32 {

	data_size := size_of(p_data^)
	aligned_size := uniform_buffer_ensure_alignment(u32(data_size))

	if INTERNAL.current_transient_buffer_offset + aligned_size >= TRANSIENT_UNIFORM_BUFFER_SIZE {
		return 0
	}

	buffer_offset :=
		get_frame_idx() * g_uniform_buffers.transient_buffer.aligned_size +
		INTERNAL.current_transient_buffer_offset

	INTERNAL.current_transient_buffer_offset += aligned_size

	transient_buffer := &g_resources.buffers[get_buffer_idx(g_uniform_buffers.transient_buffer.buffer_ref)]

	mem.copy(mem.ptr_offset(transient_buffer.mapped_ptr, buffer_offset), p_data, data_size)

	return buffer_offset
}

//---------------------------------------------------------------------------//

uniform_buffer_ensure_alignment :: proc {
	uniform_buffer_ensure_alignment_by_size,
	uniform_buffer_ensure_alignment_by_type,
}

//---------------------------------------------------------------------------//

@(private = "file")
uniform_buffer_ensure_alignment_by_type :: proc($T: typeid) -> u32 {
	return uniform_buffer_ensure_alignment_by_size(size_of(T))
}

//---------------------------------------------------------------------------//

@(private = "file")
uniform_buffer_ensure_alignment_by_size :: proc(p_size: u32) -> u32 {
	reminder := p_size % G_RENDERER.min_uniform_buffer_alignment
	return p_size + G_RENDERER.min_uniform_buffer_alignment - reminder
}

//---------------------------------------------------------------------------//

@(private = "file")
update_per_frame_data :: proc(p_dt: f32) {
	g_per_frame_data.sun = DirectionalLight {
		color     = {1, 1, 1},
		direction = {0, -1, 0},
	}

	g_uniform_buffers.frame_data_offset = uniform_buffer_create_transient_buffer(&g_per_frame_data)
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_create_view_data :: proc(p_view: RenderView) -> u32 {

	view_data := PerViewData{}

	view_data.view = p_view.view
	view_data.proj = p_view.projection
	view_data.inv_view_proj = glsl.inverse(view_data.view * view_data.proj)
	view_data.camera_pos_ws = p_view.position

	return uniform_buffer_create_transient_buffer(&view_data)
}

//---------------------------------------------------------------------------//

@(private = "file")
uniform_buffer_create_dynamic_by_size :: proc(
	p_name: common.Name,
	p_size: u32,
) -> DynamicUniformBuffer {
	buffer_ref := allocate_buffer_ref(p_name)
	buffer := &g_resources.buffers[get_buffer_idx(buffer_ref)]

	aligned_size := uniform_buffer_ensure_alignment(p_size)

	buffer.desc.flags = {.HostWrite, .Mapped}
	buffer.desc.size = aligned_size * G_RENDERER.num_frames_in_flight
	buffer.desc.usage = {.DynamicUniformBuffer}

	if create_buffer(buffer_ref) == false {
		return DynamicUniformBuffer{buffer_ref = InvalidBufferRef, aligned_size = 0}
	}

	return DynamicUniformBuffer{buffer_ref = buffer_ref, aligned_size = aligned_size}
}

//---------------------------------------------------------------------------//

@(private = "file")
uniform_buffer_create_dynamic_by_type :: proc(
	p_name: common.Name,
	$T: typeid,
) -> DynamicUniformBuffer {
	return uniform_buffer_create_dynamic(p_name, size_of(T))
}

//---------------------------------------------------------------------------//
