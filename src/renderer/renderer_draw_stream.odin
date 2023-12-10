package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:mem"

//---------------------------------------------------------------------------//

// Array of operations that can be performed on a draw stream. Those functions mutate the 
// draw info in the draw stream dispatch and call appropriate functions to configure the GPU.
// Order of these functions has to match the order of DrawStramOp enum, as those functions are indexed
// by those enum values, this way we can avoid if/else chain
@(private = "file")
g_draw_stream_ops := []proc(_: ^DrawStreamDispatch){
	draw_stream_dispatch_bind_pipeline,
	draw_stream_dispatch_bind_vertex_buffer,
	draw_stream_dispatch_bind_index_buffer,
	draw_stream_dispatch_change_bind_group,
	draw_stream_dispatch_set_instance_count,
	draw_stream_dispatch_set_first_instance,
	draw_stream_dispatch_set_draw_count,
	draw_stream_dispatcher_submit_draw,
}

//---------------------------------------------------------------------------//

@(private = "file")
DrawStreamOp :: enum u32 {
	BindPipeline,
	BindVertexBuffer,
	BindIndexBuffer,
	ChangeBindGroup,
	SetInstanceCount,
	SetFirstInstances,
	SetDrawCount,
	SubmitDraw,
}

//---------------------------------------------------------------------------//

IndexType :: enum u8 {
	UInt16,
	UInt32,
}

//---------------------------------------------------------------------------//

DrawStream :: struct {
	// Encoded draw stream data: field id and it's values
	encoded_draw_stream_data:    [dynamic]u32,
	push_constants:              [dynamic]rawptr,
	current_index_buffer_ref:    BufferRef,
	current_index_buffer_offset: u32,
	current_pipeline_ref:        PipelineRef,
	allocator:                   mem.Allocator,
}

//---------------------------------------------------------------------------//

@(private = "file")
DrawStreamDispatch :: struct {
	draw_stream:           ^DrawStream,
	draw_stream_offset:    u32,
	cmd_buff_ref:          CommandBufferRef,
	current_draw:          u32,
	current_push_constant: u32,
	pipeline_ref:          PipelineRef,
	draw_count:            u32,
	instance_count:        u32,
	first_instance:        u32,
	index_buffer_ref:      BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
BindGroupsWithOffsets :: struct {
	bind_group_ref:  BindGroupRef,
	dynamic_offsets: []u32,
}

//---------------------------------------------------------------------------//

draw_stream_create :: proc(p_draw_stream_allocator: mem.Allocator) -> DrawStream {
	draw_stream := DrawStream {
		allocator = p_draw_stream_allocator,
	}

	draw_stream.encoded_draw_stream_data = make(
		[dynamic]u32,
		(8 * common.KILOBYTE) / size_of(u32),
		p_draw_stream_allocator,
	)
	clear(&draw_stream.encoded_draw_stream_data)

	draw_stream.push_constants = make(
		[dynamic]rawptr,
		(8 * common.KILOBYTE) / size_of(rawptr),
		p_draw_stream_allocator,
	)
	clear(&draw_stream.push_constants)

	draw_stream.current_index_buffer_ref = InvalidBufferRef
	draw_stream.current_pipeline_ref = InvalidPipelineRef

	return draw_stream
}

//---------------------------------------------------------------------------//

draw_stream_dispatch :: proc(p_cmd_buff_ref: CommandBufferRef, p_draw_stream: ^DrawStream) {
	draw_stream_dispatch := DrawStreamDispatch {
		draw_stream  = p_draw_stream,
		cmd_buff_ref = p_cmd_buff_ref,
	}

	draw_stream_dispatch.current_draw = 0
	draw_stream_dispatch.current_push_constant = 0

	for draw_stream_dispatch.draw_stream_offset <
	    u32(len(p_draw_stream.encoded_draw_stream_data)) {
		op := p_draw_stream.encoded_draw_stream_data[draw_stream_dispatch.draw_stream_offset]
		draw_stream_dispatch.draw_stream_offset += 1
		g_draw_stream_ops[op](&draw_stream_dispatch)
	}
}
//---------------------------------------------------------------------------//

draw_stream_reset :: proc(p_draw_stream: ^DrawStream) {
	free_all(p_draw_stream.allocator)

	p_draw_stream.encoded_draw_stream_data = make(
		[dynamic]u32,
		(8 * common.KILOBYTE) / size_of(u32),
		p_draw_stream.allocator,
	)
	clear(&p_draw_stream.encoded_draw_stream_data)

	p_draw_stream.push_constants = make(
		[dynamic]rawptr,
		(8 * common.KILOBYTE) / size_of(rawptr),
		p_draw_stream.allocator,
	)
	clear(&p_draw_stream.push_constants)
}

//---------------------------------------------------------------------------//

draw_stream_destroy :: proc(p_draw_stream: DrawStream) {
	delete(p_draw_stream.encoded_draw_stream_data)
}

//---------------------------------------------------------------------------//

// Helper method to issue the draw stream call in the right order
draw_stream_add_draw :: proc(
	p_draw_stream: ^DrawStream,
	p_draw_count: u32,
	p_instance_count: u32,
	p_pipeline_ref: PipelineRef = InvalidPipelineRef,
	p_vertex_buffers: []OffsetBuffer = {},
	p_index_buffer: OffsetBuffer = InvalidOffsetBuffer,
	p_index_type: IndexType = .UInt32,
	p_bind_groups: []BindGroupsWithOffsets = {},
	p_push_constants: []rawptr = {},
) {

	if p_pipeline_ref != p_draw_stream.current_pipeline_ref {
		draw_stream_set_pipeline(p_draw_stream, p_pipeline_ref)
	}

	for vertex_buffers, i in p_vertex_buffers {
		draw_stream_set_vertex_buffer(
			p_draw_stream,
			vertex_buffers.buffer_ref,
			u32(i),
			vertex_buffers.offset,
		)
	}

	if p_index_buffer.buffer_ref != p_draw_stream.current_index_buffer_ref ||
	   p_index_buffer.offset != p_draw_stream.current_index_buffer_offset ||
	   p_draw_stream.current_index_buffer_ref == InvalidBufferRef {
		draw_stream_set_index_buffer(
			p_draw_stream,
			p_index_buffer.buffer_ref,
			p_index_type,
			p_index_buffer.offset,
		)
	}

	for bind_group, i in p_bind_groups {
		if bind_group.bind_group_ref == InvalidBindGroupRef {
			continue
		}
		draw_stream_set_bind_group(
			p_draw_stream,
			bind_group.bind_group_ref,
			u32(i),
			bind_group.dynamic_offsets,
		)
	}

	for push_constant in p_push_constants {
		append(&p_draw_stream.push_constants, push_constant)
	}

	draw_stream_set_draw_count(p_draw_stream, p_draw_count)
	draw_stream_set_instance_count(p_draw_stream, p_instance_count)
	draw_stream_submit_draw(p_draw_stream)
}

//---------------------------------------------------------------------------//

draw_stream_set_pipeline :: proc(p_draw_stream: ^DrawStream, p_pipeline_ref: PipelineRef) {
	draw_stream_write(p_draw_stream, .BindPipeline, p_pipeline_ref.ref)
}

//---------------------------------------------------------------------------//

draw_stream_set_vertex_buffer :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_binding: u32,
	p_offset: u32 = 0,
) {
	draw_stream_write(p_draw_stream, .BindVertexBuffer, p_buffer_ref.ref, p_binding, p_offset)
}

//---------------------------------------------------------------------------//

draw_stream_set_index_buffer :: proc(
	p_draw_stream: ^DrawStream,
	p_buffer_ref: BufferRef,
	p_index_type: IndexType,
	p_offset: u32 = 0,
) {

	p_draw_stream.current_index_buffer_ref = p_buffer_ref
	p_draw_stream.current_index_buffer_offset = p_offset

	draw_stream_write(
		p_draw_stream,
		.BindIndexBuffer,
		p_buffer_ref.ref,
		p_offset,
		u32(p_index_type),
	)
}

//---------------------------------------------------------------------------//

draw_stream_set_bind_group :: proc(
	p_draw_stream: ^DrawStream,
	p_bind_group_ref: BindGroupRef,
	p_binding: u32,
	p_dynamic_offsets: []u32,
) {
	draw_stream_write(p_draw_stream, .ChangeBindGroup, p_bind_group_ref.ref, p_binding)
	draw_stream_write_without_op(p_draw_stream, p_dynamic_offsets)
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

draw_stream_set_first_instance :: proc(p_draw_stream: ^DrawStream, p_first_instance: u32) {
	draw_stream_write(p_draw_stream, .SetInstanceCount, p_first_instance)
}

//---------------------------------------------------------------------------//

draw_stream_add_push_constants :: proc(p_draw_stream: ^DrawStream, p_push_constants: ^$T) {
	push_constants := new_clone(p_push_constants^, p_draw_stream.allocator)
	append(&p_draw_stream.push_constants, push_constants)
}

//---------------------------------------------------------------------------//

draw_stream_submit_draw :: proc(p_draw_stream: ^DrawStream) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(DrawStreamOp.SubmitDraw))
}

//---------------------------------------------------------------------------//

draw_stream_dispatch_bind_pipeline :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	pipeline_ref := PipelineRef {
		ref = draw_stream_dispatch_read_next(p_draw_stream_dispatch),
	}
	bind_pipeline(pipeline_ref, p_draw_stream_dispatch.cmd_buff_ref)
	p_draw_stream_dispatch.pipeline_ref = pipeline_ref
}

//---------------------------------------------------------------------------//

draw_stream_dispatch_bind_vertex_buffer :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	vertex_buffer_ref := BufferRef {
		ref = draw_stream_dispatch_read_next(p_draw_stream_dispatch),
	}
	binding := draw_stream_dispatch_read_next(p_draw_stream_dispatch)
	buffer_offset := draw_stream_dispatch_read_next(p_draw_stream_dispatch)

	backend_draw_stream_dispatch_bind_vertex_buffer(
		p_draw_stream_dispatch.cmd_buff_ref,
		vertex_buffer_ref,
		binding,
		buffer_offset,
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
	p_draw_stream_dispatch.index_buffer_ref = index_buffer_ref
	backend_draw_stream_dispatch_bind_index_buffer(
		p_draw_stream_dispatch.cmd_buff_ref,
		index_buffer_ref,
		buffer_offset,
		index_type,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_draw_count :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.draw_count = draw_stream_dispatch_read_next(p_draw_stream_dispatch)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_instance_count :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.instance_count = draw_stream_dispatch_read_next(p_draw_stream_dispatch)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_set_first_instance :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	p_draw_stream_dispatch.first_instance = draw_stream_dispatch_read_next(p_draw_stream_dispatch)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_change_bind_group :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	bind_group_ref := BindGroupRef{draw_stream_dispatch_read_next(p_draw_stream_dispatch)}
	binding := draw_stream_dispatch_read_next(p_draw_stream_dispatch)
	dynamic_offsets := draw_stream_dispatch_read_slice(p_draw_stream_dispatch)
	bind_bind_group(
		p_draw_stream_dispatch.cmd_buff_ref,
		p_draw_stream_dispatch.pipeline_ref,
		bind_group_ref,
		binding,
		dynamic_offsets,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatcher_submit_draw :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) {
	assert(p_draw_stream_dispatch.pipeline_ref != InvalidPipelineRef)

	// Collect push constants for the current pipeline
	pipeline := &g_resources.pipelines[get_pipeline_idx(p_draw_stream_dispatch.pipeline_ref)]

	push_constants_start := p_draw_stream_dispatch.current_push_constant
	push_constants_count := u32(len(pipeline.desc.push_constants))

	push_constants := p_draw_stream_dispatch.draw_stream.push_constants[push_constants_start:push_constants_start +
	push_constants_count]

	p_draw_stream_dispatch.current_push_constant += push_constants_count

	if p_draw_stream_dispatch.index_buffer_ref == InvalidBufferRef {
		backend_draw_stream_submit_draw(
			p_draw_stream_dispatch.cmd_buff_ref,
			p_draw_stream_dispatch.draw_count,
			p_draw_stream_dispatch.instance_count,
		)
	} else {
		backend_draw_stream_submit_indexed_draw(
			p_draw_stream_dispatch.cmd_buff_ref,
			p_draw_stream_dispatch.draw_count,
			p_draw_stream_dispatch.instance_count,
			p_draw_stream_dispatch.first_instance,
			p_draw_stream_dispatch.pipeline_ref,
			push_constants,
		)
	}

	p_draw_stream_dispatch.current_draw += 1
}

//---------------------------------------------------------------------------//

@(private = "file")
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
draw_stream_write_without_op :: proc {
	draw_stream_write_value_without_op,
	draw_stream_write_values_without_op,
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_write_value_without_op :: #force_inline proc(
	p_draw_stream: ^DrawStream,
	p_value: u32,
) {
	append(&p_draw_stream.encoded_draw_stream_data, p_value)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_write_values_without_op :: #force_inline proc(
	p_draw_stream: ^DrawStream,
	p_values: []u32,
) {
	append(&p_draw_stream.encoded_draw_stream_data, u32(len(p_values)))
	for value in p_values {
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

@(private = "file")
draw_stream_dispatch_read_slice :: proc(p_draw_stream_dispatch: ^DrawStreamDispatch) -> []u32 {
	slice_len := draw_stream_dispatch_read_next(p_draw_stream_dispatch)
	slice_start := p_draw_stream_dispatch.draw_stream_offset
	p_draw_stream_dispatch.draw_stream_offset += slice_len
	return(
		p_draw_stream_dispatch.draw_stream.encoded_draw_stream_data[slice_start:slice_start +
		slice_len] \
	)
}


//---------------------------------------------------------------------------//
