package renderer

//---------------------------------------------------------------------------//

import "core:mem"

//---------------------------------------------------------------------------//

DrawInfo :: struct {
	vertex_offset:        u32,
	vertex_count:         u32,
	instance_offset:      u32,
	instance_count:       u32,
	vertex_buffer_offset: u32,
	vertex_buffer_ref:    BufferRef,
}

//---------------------------------------------------------------------------//

IndexType :: enum {
	UInt16,
	UInt32,
}

//---------------------------------------------------------------------------//

IndexedDrawInfo :: struct {
	index_type:           IndexType,
	index_offset:         u32,
	index_count:          u32,
	instance_offset:      u32,
	instance_count:       u32,
	vertex_buffer_offset: u32,
	index_buffer_offset:  u32,
	vertex_buffer_ref:    BufferRef,
	index_buffer_ref:     BufferRef,
}

//---------------------------------------------------------------------------//

DrawStreamOperation :: enum {
	Draw,
	IndexedDraw,
	ChangeGlobalBindGroups,
	ChangeInstanceBindGroups,
	ChangePipeline,
}

//---------------------------------------------------------------------------//

BindGroupChange :: struct {
	bind_group_ref:  BindGroupRef,
	dynamic_offsets: []u32,
}

//---------------------------------------------------------------------------//


DrawStream :: struct {
	draw_infos:                      [dynamic]DrawInfo,
	indexed_draw_infos:              [dynamic]IndexedDrawInfo,
	pipeline_changes:                [dynamic]PipelineRef,
	global_bind_group_changes:       [dynamic]BindGroupChange,
	instance_bind_group_changes:     [dynamic]BindGroupChange,
	operations:                      [dynamic]DrawStreamOperation,
	next_draw:                       u32,
	next_indexed_draw:               u32,
	next_global_bind_group_change:   u32,
	next_instance_bind_group_change: u32,
	next_pipeline:                   u32,
	allocator:                       mem.Allocator,
	current_pipeline_ref:            PipelineRef,
}

//---------------------------------------------------------------------------//

draw_stream_init :: proc(p_allocator: mem.Allocator, p_draw_stream: ^DrawStream) {
	p_draw_stream.draw_infos = make([dynamic]DrawInfo, p_allocator)
	p_draw_stream.indexed_draw_infos = make([dynamic]IndexedDrawInfo, p_allocator)
	p_draw_stream.global_bind_group_changes = make([dynamic]BindGroupChange, p_allocator)
	p_draw_stream.instance_bind_group_changes = make([dynamic]BindGroupChange, p_allocator)
	p_draw_stream.pipeline_changes = make([dynamic]PipelineRef, p_allocator)
	p_draw_stream.operations = make([dynamic]DrawStreamOperation, p_allocator)
	p_draw_stream.allocator = p_allocator
}

draw_stream_reset :: proc(p_draw_stream: ^DrawStream) {
	p_draw_stream.next_draw = 0
	p_draw_stream.next_indexed_draw = 0
	p_draw_stream.next_global_bind_group_change = 0
	p_draw_stream.next_instance_bind_group_change = 0
	p_draw_stream.next_pipeline = 0
	p_draw_stream.current_pipeline_ref = InvalidPipelineRef
}

//---------------------------------------------------------------------------//

draw_stream_free :: proc(p_draw_stream: ^DrawStream) {
	delete(p_draw_stream.draw_infos)
	delete(p_draw_stream.indexed_draw_infos)
	delete(p_draw_stream.global_bind_group_changes)
	delete(p_draw_stream.instance_bind_group_changes)
	delete(p_draw_stream.pipeline_changes)
	delete(p_draw_stream.operations)
}

//---------------------------------------------------------------------------//

draw_stream_submit :: proc(p_cmd_buff_ref: CommandBufferRef, p_draw_stream: ^DrawStream) {
	cmd_buff := get_command_buffer(p_cmd_buff_ref)
	for operation in p_draw_stream.operations {
		draw_stream_operations[operation](p_cmd_buff_ref, cmd_buff, p_draw_stream)
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_operations := []proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
){
	draw_stream_dispatch_draw_cmd,
	draw_stream_dispatch_indexed_draw_cmd,
	draw_stream_update_global_bind_group,
	draw_stream_update_instance_bind_group,
	draw_stream_update_pipeline,
}

//---------------------------------------------------------------------------//

draw_stream_add_draw :: proc(p_draw_stream: ^DrawStream) -> ^DrawInfo {
	append(&p_draw_stream.operations, DrawStreamOperation.Draw)
	draw_info := DrawInfo{}
	append(&p_draw_stream.draw_infos, draw_info)
	return &p_draw_stream.draw_infos[len(p_draw_stream.draw_infos) - 1]
}

//---------------------------------------------------------------------------//

draw_stream_add_indexed_draw :: proc(p_draw_stream: ^DrawStream) -> ^IndexedDrawInfo {
	append(&p_draw_stream.operations, DrawStreamOperation.IndexedDraw)
	append(&p_draw_stream.indexed_draw_infos, IndexedDrawInfo{})
	return &p_draw_stream.indexed_draw_infos[len(p_draw_stream.indexed_draw_infos) - 1]
}
//---------------------------------------------------------------------------//

draw_stream_update_global_bind_group :: proc(
	p_draw_stream: ^DrawStream,
	p_per_frame_dynamic_offset: int,
	p_per_view_dynamic_offset: int,
) {
	append(&p_draw_stream.operations, DrawStreamOperation.ChangeGlobalBindGroups)
	append(&p_draw_stream.global_bind_group_changes, BindGroupChange{})

	bind_group_change := &p_draw_stream.global_bind_group_changes[len(p_draw_stream.global_bind_group_changes) - 1]
	bind_group_change.bind_group_ref = G_RENDERER.global_bind_group_ref

	dynamic_offsets_count := 0
	if p_per_frame_dynamic_offset >= 0 {
		dynamic_offsets_count += 1
	}
	if p_per_view_dynamic_offset >= 0 {
		dynamic_offsets_count += 1
	}

	bind_group_change.dynamic_offsets = make([]u32, dynamic_offsets_count, p_draw_stream.allocator)

	dynamic_offsets_idx := 0
	
	if p_per_frame_dynamic_offset >= 0 {
		bind_group_change.dynamic_offsets[dynamic_offsets_idx] = u32(p_per_frame_dynamic_offset)
		dynamic_offsets_idx += 1
	}

	if p_per_view_dynamic_offset >= 0 {
		bind_group_change.dynamic_offsets[dynamic_offsets_idx] = u32(p_per_view_dynamic_offset)
		dynamic_offsets_idx += 1
	}
}
//---------------------------------------------------------------------------//

draw_stream_update_instance_bind_group :: proc(
	p_draw_stream: ^DrawStream,
	p_bind_group_ref: BindGroupRef,
	p_dynamic_offsets: []u32,
) {
	append(&p_draw_stream.operations, DrawStreamOperation.ChangeInstanceBindGroups)
	append(&p_draw_stream.global_bind_group_changes, BindGroupChange{})

	bind_group_change := &p_draw_stream.global_bind_group_changes[len(p_draw_stream.global_bind_group_changes) - 1]
	bind_group_change.bind_group_ref = p_bind_group_ref
	bind_group_change.dynamic_offsets = make(
		[]u32,
		len(p_dynamic_offsets),
		p_draw_stream.allocator,
	)

	for dynamic_offset, i in p_dynamic_offsets {
		bind_group_change.dynamic_offsets[i] = dynamic_offset
	}
}
//---------------------------------------------------------------------------//

draw_stream_change_pipeline :: proc(p_draw_stream: ^DrawStream, p_pipeline_ref: PipelineRef) {
	append(&p_draw_stream.operations, DrawStreamOperation.ChangePipeline)
	append(&p_draw_stream.pipeline_changes, p_pipeline_ref)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_draw_cmd :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
) {
	backend_draw_stream_dispatch_draw_cmd(
		p_draw_stream,
		p_cmd_buff,
		&p_draw_stream.draw_infos[p_draw_stream.next_draw],
	)
	p_draw_stream.next_draw += 1
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_dispatch_indexed_draw_cmd :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
) {
	backend_draw_stream_dispatch_indexed_draw_cmd(
		p_draw_stream,
		p_cmd_buff,
		&p_draw_stream.indexed_draw_infos[p_draw_stream.next_indexed_draw],
	)
	p_draw_stream.next_indexed_draw += 1
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_update_pipeline :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
) {
	new_pipeline_ref := p_draw_stream.pipeline_changes[p_draw_stream.next_pipeline]
	p_draw_stream.next_pipeline += 1

	pipeline := get_pipeline(new_pipeline_ref)
	p_draw_stream.current_pipeline_ref = new_pipeline_ref

	backend_draw_stream_change_pipeline(p_draw_stream, p_cmd_buff, pipeline)

	assert(p_draw_stream.current_pipeline_ref != InvalidPipelineRef)
	bind_bind_group(
		p_cmd_buff_ref,
		p_draw_stream.current_pipeline_ref,
		G_RENDERER.bindless_textures_array_bind_group_ref,
		2,
		nil,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_update_global_bind_group :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
) {
	bind_group_change :=
		p_draw_stream.global_bind_group_changes[p_draw_stream.next_global_bind_group_change]
	p_draw_stream.next_global_bind_group_change += 1

	assert(p_draw_stream.current_pipeline_ref != InvalidPipelineRef)
	bind_bind_group(
		p_cmd_buff_ref,
		p_draw_stream.current_pipeline_ref,
		bind_group_change.bind_group_ref,
		1,
		bind_group_change.dynamic_offsets,
	)

}

//---------------------------------------------------------------------------//

@(private = "file")
draw_stream_update_instance_bind_group :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
	p_draw_stream: ^DrawStream,
) {
	bind_group_change :=
		p_draw_stream.instance_bind_group_changes[p_draw_stream.next_instance_bind_group_change]
	p_draw_stream.next_instance_bind_group_change += 1

	assert(p_draw_stream.current_pipeline_ref != InvalidPipelineRef)
	bind_bind_group(
		p_cmd_buff_ref,
		p_draw_stream.current_pipeline_ref,
		bind_group_change.bind_group_ref,
		0,
		bind_group_change.dynamic_offsets,
	)

}

//---------------------------------------------------------------------------//
