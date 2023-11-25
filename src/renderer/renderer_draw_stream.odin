package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:mem"
import "core:runtime"
import "core:slice"

//---------------------------------------------------------------------------//

// Array of operations that can be performed on a draw stream. Those functions mutate the 
// draw info in the draw stream dispatch and call appropriate functions to configure the GPU.
// Order of these functions has to match the order of DrawStramOp enum, as those functions are indexed
// by those enum values, this way we can avoid if/else chain
@(private = "file")
g_draw_stream_ops := []proc(_: ^DrawStreamDispatch){
	draw_stream_dispatch_bind_pipeline,
	draw_stream_dispatch_bind_vertex_buffer_0,
	draw_stream_dispatch_bind_vertex_buffer_1,
	draw_stream_dispatch_bind_vertex_buffer_2,
	draw_stream_dispatch_bind_index_buffer,
	draw_stream_dispatch_set_vertex_offset,
	draw_stream_dispatch_set_draw_count,
	draw_stream_dispatch_set_instance_count,
	draw_stream_dispatch_change_bind_group_0,
	draw_stream_dispatch_change_bind_group_1,
	draw_stream_dispatch_change_bind_group_2,
	draw_stream_dispatch_set_dynamic_offsets_0,
	draw_stream_dispatch_set_dynamic_offsets_1,
	draw_stream_dispatch_set_dynamic_offsets_2,
	draw_stream_dispatcher_submit_draw,
}

//---------------------------------------------------------------------------//

@(private = "file")
DrawStreamOp :: enum u32 {
	BindPipeline,
	BindVertexBuffer0,
	BindVertexBuffer1,
	BindVertexBuffer2,
	BindIndexBuffer,
	SetVertexOffset,
	SetDrawCount,
	SetInstanceCount,
	ChangeBindGroup0,
	ChangeBindGroup1,
	ChangeBindGroup2,
	SetDynamicOffsets0,
	SetDynamicOffsets1,
	SetDynamicOffsets2,
	SubmitDraw,
}

//---------------------------------------------------------------------------//

IndexType :: enum u8 {
	UInt16,
	UInt32,
}

//---------------------------------------------------------------------------//

@(private = "file")
DrawInfo :: struct {
	pipeline_ref:        PipelineRef, // 4
	vertex_buffer_ref_0: BufferRef, // 8
	vertex_buffer_ref_1: BufferRef, // 12
	vertex_buffer_ref_2: BufferRef, // 16
	index_buffer_ref:    BufferRef, // 20
	vertex_offset:       u32, // 28
	draw_count:          u32, // 32
	instance_count:      u32, // 36
	bind_group_0_ref:    BindGroupRef, // 40
	bind_group_1_ref:    BindGroupRef, // 44
	bind_group_2_ref:    BindGroupRef, // 48
	dynamic_offsets_0:   []u32, // 52
	dynamic_offsets_1:   []u32, // 56
	dynamic_offsets_2:   []u32, // 60
	index_type:          IndexType, //pad to 64 byte cacheline
}

//---------------------------------------------------------------------------//

DrawStream :: struct {
	// Encoded draw stream data: field id and it's values
	encoded_draw_stream_data: [dynamic]u32,
	current_index_buffer:     BufferRef,
}

//---------------------------------------------------------------------------//

@(private = "file")
DrawStreamDispatch :: struct {
	draw_info:          DrawInfo,
	draw_stream:        DrawStream,
	draw_stream_offset: u32,
	cmd_buff_ref:       CommandBufferRef,
}

//---------------------------------------------------------------------------//

draw_stream_create :: proc(p_draw_stream_allocator: mem.Allocator) -> DrawStream {
	draw_stream := DrawStream{}

	draw_stream.encoded_draw_stream_data = make(
		[dynamic]u32,
		(8 * common.KILOBYTE) / size_of(u32),
		p_draw_stream_allocator,
	)

	draw_stream.current_index_buffer = InvalidBufferRef

	return draw_stream
}

//---------------------------------------------------------------------------//

draw_stream_dispatch :: proc(p_cmd_buff_ref: CommandBufferRef, p_draw_stream: DrawStream) {
	draw_stream_dispatch := DrawStreamDispatch {
		draw_stream  = p_draw_stream,
		cmd_buff_ref = p_cmd_buff_ref,
	}
	draw_stream_dispatch.draw_info = DrawInfo {
		vertex_buffer_ref_0 = InvalidBufferRef,
		vertex_buffer_ref_1 = InvalidBufferRef,
		vertex_buffer_ref_2 = InvalidBufferRef,
		index_buffer_ref    = InvalidBufferRef,
		bind_group_0_ref    = InvalidBindGroup,
		bind_group_1_ref    = InvalidBindGroup,
		bind_group_2_ref    = InvalidBindGroup,
	}

	draw_stream_dispatch.draw_info.bind_group_0_ref = InvalidBindGroup
	draw_stream_dispatch.draw_info.bind_group_1_ref = InvalidBindGroup
	draw_stream_dispatch.draw_info.bind_group_2_ref = InvalidBindGroup

	for draw_stream_dispatch.draw_stream_offset <
	    u32(len(p_draw_stream.encoded_draw_stream_data)) {
		op := p_draw_stream.encoded_draw_stream_data[draw_stream_dispatch.draw_stream_offset]
		draw_stream_dispatch.draw_stream_offset += 1
		g_draw_stream_ops[op](&draw_stream_dispatch)
	}
}
//---------------------------------------------------------------------------//

draw_stream_reset :: proc(p_draw_stream: ^DrawStream) {
	(^runtime.Raw_Dynamic_Array)(&p_draw_stream.encoded_draw_stream_data).len = 0
}

//---------------------------------------------------------------------------//

draw_stream_destroy :: proc(p_draw_stream: DrawStream) {
	delete(p_draw_stream.encoded_draw_stream_data)
}

//---------------------------------------------------------------------------//


// Helper method to issue the draw stream call in the right order
draw_stream_add_draw :: proc(
	p_draw_stream: ^DrawStream,
	p_pipeline_ref: PipelineRef = InvalidPipelineRef,
	p_vertex_buffer_ref_0: BufferRef = InvalidBufferRef,
	p_vertex_buffer_ref_1: BufferRef = InvalidBufferRef,
	p_vertex_buffer_ref_2: BufferRef = InvalidBufferRef,
	p_index_buffer_ref: BufferRef = InvalidBufferRef,
	p_index_offset: u32 = 0,
	p_vertex_offset: u32 = 0,
	p_draw_count: u32 = 0,
	p_instance_count: u32 = 0,
	p_index_type: IndexType = .UInt16,
	p_bind_group_0_ref: BindGroupRef = InvalidBindGroup,
	p_bind_group_1_ref: BindGroupRef = InvalidBindGroup,
	p_bind_group_2_ref: BindGroupRef = InvalidBindGroup,
	p_dynamic_offsets_0: []u32 = nil,
	p_dynamic_offsets_1: []u32 = nil,
	p_dynamic_offsets_2: []u32 = nil,
) {

	if p_pipeline_ref != InvalidPipelineRef {
		draw_stream_bind_pipeline(p_draw_stream, p_pipeline_ref)
	}

	if p_dynamic_offsets_0 != nil {
		draw_stream_set_dynamic_offsets_0(p_draw_stream, p_dynamic_offsets_0)
	}

	if p_dynamic_offsets_1 != nil {
		draw_stream_set_dynamic_offsets_1(p_draw_stream, p_dynamic_offsets_1)
	}

	if p_dynamic_offsets_2 != nil {
		draw_stream_set_dynamic_offsets_2(p_draw_stream, p_dynamic_offsets_2)
	}

	if p_bind_group_0_ref != InvalidBindGroup {
		draw_stream_set_bind_group_0(p_draw_stream, p_bind_group_0_ref)
	}

	if p_bind_group_1_ref != InvalidBindGroup {
		draw_stream_set_bind_group_1(p_draw_stream, p_bind_group_1_ref)
	}

	if p_bind_group_2_ref != InvalidBindGroup {
		draw_stream_set_bind_group_2(p_draw_stream, p_bind_group_2_ref)
	}

	if p_vertex_buffer_ref_0 != InvalidBufferRef {
		draw_stream_set_vertex_buffer_0(p_draw_stream, p_vertex_buffer_ref_0)
	}

	if p_vertex_buffer_ref_1 != InvalidBufferRef {
		draw_stream_set_vertex_buffer_1(p_draw_stream, p_vertex_buffer_ref_1)
	}

	if p_vertex_buffer_ref_2 != InvalidBufferRef {
		draw_stream_set_vertex_buffer_2(p_draw_stream, p_vertex_buffer_ref_2)
	}

	if p_index_buffer_ref != p_draw_stream.current_index_buffer {
		draw_stream_set_index_buffer(
			p_draw_stream,
			p_index_buffer_ref,
			p_index_type,
			p_index_offset,
		)
	}


	draw_stream_set_vertex_offset(p_draw_stream, p_vertex_offset)
	draw_stream_set_draw_count(p_draw_stream, p_draw_count)
	draw_stream_set_instance_count(p_draw_stream, p_instance_count)
	draw_stream_submit_draw(p_draw_stream)
}

//---------------------------------------------------------------------------//

draw_stream_submit_draw :: proc(p_draw_stream: ^DrawStream) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(DrawStreamOp.SubmitDraw))
}

//---------------------------------------------------------------------------//

draw_stream_bind_pipeline :: proc(p_draw_stream: ^DrawStream, p_pipeline_ref: PipelineRef) {
	draw_stream_write(p_draw_stream, .BindPipeline, p_pipeline_ref.ref)
}

//---------------------------------------------------------------------------//

draw_stream_set_vertex_buffer_0 :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_offset: u32 = 0,
) {
	draw_stream_write(p_draw_stream, .BindVertexBuffer0, p_buffer_ref.ref, p_offset)
}
//---------------------------------------------------------------------------//

draw_stream_set_vertex_buffer_1 :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_offset: u32 = 0,
) {
	draw_stream_write(p_draw_stream, .BindVertexBuffer1, p_buffer_ref.ref, p_offset)
}

//---------------------------------------------------------------------------//

draw_stream_set_vertex_buffer_2 :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_offset: u32 = 0,
) {
	draw_stream_write(p_draw_stream, .BindVertexBuffer2, p_buffer_ref.ref, p_offset)
}

//---------------------------------------------------------------------------//

draw_stream_set_index_buffer :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_index_type: IndexType,
	p_offset: u32 = 0,
) {
	draw_stream_write(
		p_draw_stream,
		.BindIndexBuffer,
		p_buffer_ref.ref,
		p_offset,
		u32(p_index_type),
	)
}

//---------------------------------------------------------------------------//

draw_stream_set_vertex_offset :: proc(p_draw_stream: ^DrawStream, p_offset: u32) {
	draw_stream_write(p_draw_stream, .SetVertexOffset, p_offset)
}

//---------------------------------------------------------------------------//

draw_stream_set_draw_count :: proc(p_draw_stream: ^DrawStream, p_draw_count: u32) {
	draw_stream_write(p_draw_stream, .SetDrawCount, p_draw_count)
}

//---------------------------------------------------------------------------//

draw_stream_set_instance_count :: proc(p_draw_stream: ^DrawStream, p_instance_count: u32) {
	draw_stream_write(p_draw_stream, .SetInstanceCount, p_instance_count)

}
//---------------------------------------------------------------------------//

draw_stream_set_bind_group_0 :: proc(p_draw_stream: ^DrawStream, p_bind_group_ref: BindGroupRef) {
	draw_stream_write(p_draw_stream, .ChangeBindGroup0, p_bind_group_ref.ref)
}

//---------------------------------------------------------------------------//

draw_stream_set_bind_group_1 :: proc(p_draw_stream: ^DrawStream, p_bind_group_ref: BindGroupRef) {
	draw_stream_write(p_draw_stream, .ChangeBindGroup1, p_bind_group_ref.ref)
}
//---------------------------------------------------------------------------//


draw_stream_set_bind_group_2 :: proc(p_draw_stream: ^DrawStream, p_bind_group_ref: BindGroupRef) {
	draw_stream_write(p_draw_stream, .ChangeBindGroup2, p_bind_group_ref.ref)
}

//---------------------------------------------------------------------------//
draw_stream_set_dynamic_offsets_0 :: proc(p_draw_stream: ^DrawStream, p_dynamic_offsets: []u32) {
	draw_stream_write_slice(p_draw_stream, .SetDynamicOffsets0, p_dynamic_offsets)
}

//---------------------------------------------------------------------------//
draw_stream_set_dynamic_offsets_1 :: proc(p_draw_stream: ^DrawStream, p_dynamic_offsets: []u32) {
	draw_stream_write_slice(p_draw_stream, .SetDynamicOffsets1, p_dynamic_offsets)
}
//---------------------------------------------------------------------------//

draw_stream_set_dynamic_offsets_2 :: proc(p_draw_stream: ^DrawStream, p_dynamic_offsets: []u32) {
	draw_stream_write_slice(p_draw_stream, .SetDynamicOffsets2, p_dynamic_offsets)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_pipeline :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	pipeline_ref := PipelineRef {
		ref = draw_stream_dispatch_read_next(p_draw_stream_dispatch),
	}
	bind_pipeline(pipeline_ref, p_draw_stream_dispatch.cmd_buff_ref)
	p_draw_stream_dispatch.draw_info.pipeline_ref = pipeline_ref
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_vertex_buffer_0 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.vertex_buffer_ref_0 = draw_stream_dispatch_bind_vertex_buffer(
		p_draw_stream_dispatch,
		0,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_vertex_buffer_1 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.vertex_buffer_ref_1 = draw_stream_dispatch_bind_vertex_buffer(
		p_draw_stream_dispatch,
		1,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_vertex_buffer_2 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.vertex_buffer_ref_2 = draw_stream_dispatch_bind_vertex_buffer(
		p_draw_stream_dispatch,
		2,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_index_buffer :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	index_buffer_ref := BufferRef {
		ref = draw_stream_dispatch_read_next(p_draw_stream_dispatch),
	}
	buffer_offset := draw_stream_dispatch_read_next(p_draw_stream_dispatch)
	index_type := IndexType(draw_stream_dispatch_read_next(p_draw_stream_dispatch))

	p_draw_stream_dispatch.draw_info.index_buffer_ref = index_buffer_ref

	backend_draw_stream_dispatch_bind_index_buffer(
		p_draw_stream_dispatch.cmd_buff_ref,
		index_buffer_ref,
		buffer_offset,
		index_type,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_vertex_offset :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.vertex_offset = draw_stream_dispatch_read_next(
		p_draw_stream_dispatch,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_draw_count :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.draw_count = draw_stream_dispatch_read_next(
		p_draw_stream_dispatch,
	)
}


//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_instance_count :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.instance_count = draw_stream_dispatch_read_next(
		p_draw_stream_dispatch,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_change_bind_group_0 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.bind_group_0_ref = draw_stream_dispatch_change_bind_group(
		p_draw_stream_dispatch,
		0,
		p_draw_stream_dispatch.draw_info.dynamic_offsets_0,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_change_bind_group_1 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.bind_group_1_ref = draw_stream_dispatch_change_bind_group(
		p_draw_stream_dispatch,
		1,
		p_draw_stream_dispatch.draw_info.dynamic_offsets_1,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_change_bind_group_2 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.bind_group_2_ref = draw_stream_dispatch_change_bind_group(
		p_draw_stream_dispatch,
		2,
		p_draw_stream_dispatch.draw_info.dynamic_offsets_2,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_dynamic_offsets_0 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.dynamic_offsets_0 = draw_stream_dispatch_set_dynamic_offsets(
		p_draw_stream_dispatch,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_dynamic_offsets_1 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.dynamic_offsets_1 = draw_stream_dispatch_set_dynamic_offsets(
		p_draw_stream_dispatch,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_dynamic_offsets_2 :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_info.dynamic_offsets_2 = draw_stream_dispatch_set_dynamic_offsets(
		p_draw_stream_dispatch,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_dynamic_offsets :: proc(
	p_draw_stream_dispatch: ^DrawStreamDispatch,
) -> []u32 {
	dynamic_offsets_count := draw_stream_dispatch_read_next(p_draw_stream_dispatch)
	dynamic_offsets_ptr := &p_draw_stream_dispatch.draw_stream.encoded_draw_stream_data[p_draw_stream_dispatch.draw_stream_offset]
	p_draw_stream_dispatch.draw_stream_offset += dynamic_offsets_count
	return slice.from_ptr(dynamic_offsets_ptr, int(dynamic_offsets_count))
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_change_bind_group :: proc(
	p_draw_stream_dispatch: ^DrawStreamDispatch,
	p_target: u32,
	p_dynamic_offsets: []u32,
) -> BindGroupRef {
	bind_group_ref := BindGroupRef{draw_stream_dispatch_read_next(p_draw_stream_dispatch)}
	bind_bind_group(
		p_draw_stream_dispatch.cmd_buff_ref,
		p_draw_stream_dispatch.draw_info.pipeline_ref,
		bind_group_ref,
		p_target,
		p_dynamic_offsets,
	)
	return bind_group_ref
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_bind_vertex_buffer :: #force_inline proc(
	p_draw_stream_dispatch: ^DrawStreamDispatch,
	p_bind_point: u32,
) -> BufferRef {
	vertex_buffer_ref := BufferRef {
		ref = draw_stream_dispatch_read_next(p_draw_stream_dispatch),
	}
	buffer_offset := draw_stream_dispatch_read_next(p_draw_stream_dispatch)

	backend_draw_stream_dispatch_bind_vertex_buffer(
		p_draw_stream_dispatch.cmd_buff_ref,
		vertex_buffer_ref,
		p_bind_point,
		buffer_offset,
	)

	return vertex_buffer_ref
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatcher_submit_draw :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	assert(p_draw_stream_dispatch.draw_info.pipeline_ref != InvalidPipelineRef)
	assert(
		p_draw_stream_dispatch.draw_info.vertex_buffer_ref_0 != InvalidBufferRef ||
		p_draw_stream_dispatch.draw_info.vertex_buffer_ref_0 != InvalidBufferRef ||
		p_draw_stream_dispatch.draw_info.vertex_buffer_ref_0 != InvalidBufferRef,
	)

	if p_draw_stream_dispatch.draw_info.index_buffer_ref == InvalidBufferRef {
		backend_draw_stream_submit_draw(
			p_draw_stream_dispatch.cmd_buff_ref,
			p_draw_stream_dispatch.draw_info.vertex_offset,
			p_draw_stream_dispatch.draw_info.draw_count,
			p_draw_stream_dispatch.draw_info.instance_count,
		)
	} else {
		backend_draw_stream_submit_indexed_draw(
			p_draw_stream_dispatch.cmd_buff_ref,
			p_draw_stream_dispatch.draw_info.draw_count,
			p_draw_stream_dispatch.draw_info.instance_count,
		)

	}
}

//---------------------------------------------------------------------------//

draw_stream_write :: proc {
	draw_stream_write_value,
	draw_stream_write_values,
}

//---------------------------------------------------------------------------//


@(private = "file")
draw_stream_write_value :: #force_inline proc(
	p_draw_stream: ^DrawStream,
	p_op: DrawStreamOp,
	p_value: u32,
) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(p_op))
	append(&p_draw_stream.encoded_draw_stream_data, p_value)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_write_values :: #force_inline proc(
	p_draw_stream: ^DrawStream,
	p_op: DrawStreamOp,
	p_values: ..u32,
) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(p_op))
	for value in p_values {
		append(&p_draw_stream.encoded_draw_stream_data, value)
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_write_slice :: #force_inline proc(
	p_draw_stream: ^DrawStream,
	p_op: DrawStreamOp,
	p_slice: []u32,
) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(p_op))
	append(&p_draw_stream.encoded_draw_stream_data, u32(len(p_slice)))
	for value in p_slice {
		append(&p_draw_stream.encoded_draw_stream_data, value)
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_read_next :: #force_inline proc(
	p_draw_stream_dispatch: ^DrawStreamDispatch,
) -> u32 {
	value :=
		p_draw_stream_dispatch.draw_stream.encoded_draw_stream_data[p_draw_stream_dispatch.draw_stream_offset]
	p_draw_stream_dispatch.draw_stream_offset += 1
	return value
}

//---------------------------------------------------------------------------//
