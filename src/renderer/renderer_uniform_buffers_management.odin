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
	view:              glsl.mat4x4,
	proj:              glsl.mat4x4,
	inv_view_proj:     glsl.mat4x4,
	inv_proj:          glsl.mat4x4,
	camera_pos_ws:     glsl.vec3,
	camera_near_plane: f32,
	camera_forward_ws: glsl.vec3,
	_padding1:         f32,
	camera_up_ws:      glsl.vec3,
	_padding2:         f32,
}

//---------------------------------------------------------------------------//

@(private)
g_per_frame_data: struct #packed {
	sun:                        DirectionalLight,
	
	delta_time: 				f32,
	time: 						f32,
	num_shadow_cascades:        u32,
	padding0: 					glsl.ivec2,

	frame_id_mod_2:             u32,
	frame_id_mod_4:             u32,
	frame_id_mod_16:            u32,
	frame_id_mod_64:            u32,
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
uniform_buffer_update :: proc(p_dt: f32) {
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

	transient_buffer := &g_resources.buffers[buffer_get_idx(g_uniform_buffers.transient_buffer.buffer_ref)]

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

	g_per_frame_data.time += p_dt
	g_per_frame_data.delta_time = p_dt

	g_per_frame_data.sun.color = {1, 1, 1}
	g_per_frame_data.sun.strength = 128000
	g_per_frame_data.sun.direction = {0, -1, 0}

	g_per_frame_data.frame_id_mod_2 = get_frame_id() % 2
	g_per_frame_data.frame_id_mod_4 = get_frame_id() % 4
	g_per_frame_data.frame_id_mod_16 = get_frame_id() % 16
	g_per_frame_data.frame_id_mod_64 = get_frame_id() % 64

	g_per_frame_data.num_shadow_cascades = G_RENDERER_SETTINGS.num_shadow_cascades
	g_per_frame_data.sun.debug_draw_cascades = 1 if G_RENDERER_SETTINGS.debug_draw_shadow_cascades else 0
	g_per_frame_data.sun.shadow_sampling_radius = G_RENDERER_SETTINGS.directional_light_shadow_sampling_radius

	g_uniform_buffers.frame_data_offset = uniform_buffer_create_transient_buffer(&g_per_frame_data)
}

//---------------------------------------------------------------------------//

@(private)
uniform_buffer_create_view_data :: proc(p_view: RenderView) -> u32 {

	view_data := PerViewData{}

	view_data.view = p_view.view
	view_data.proj = p_view.projection
	view_data.inv_view_proj = glsl.inverse(view_data.proj * view_data.view)
	view_data.inv_proj = glsl.inverse(view_data.proj)
	view_data.camera_pos_ws = p_view.position
	view_data.camera_near_plane = p_view.near_plane
	view_data.camera_forward_ws = p_view.forward
	view_data.camera_up_ws = p_view.up

	return uniform_buffer_create_transient_buffer(&view_data)
}

//---------------------------------------------------------------------------//

@(private = "file")
uniform_buffer_create_dynamic_by_size :: proc(
	p_name: common.Name,
	p_size: u32,
) -> DynamicUniformBuffer {
	buffer_ref := buffer_allocate(p_name)
	buffer := &g_resources.buffers[buffer_get_idx(buffer_ref)]

	aligned_size := uniform_buffer_ensure_alignment(p_size)

	buffer.desc.flags = {.HostWrite, .Mapped}
	buffer.desc.size = aligned_size * G_RENDERER.num_frames_in_flight
	buffer.desc.usage = {.DynamicUniformBuffer}

	if buffer_create(buffer_ref) == false {
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
