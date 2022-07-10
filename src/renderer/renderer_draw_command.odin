package renderer

DrawCommand :: struct{
    vertex_buffer: BufferRef,
    index_buffer: BufferRef,
    vertex_count: i32,
    vertex_buffer_offset: u32,
    index_count: i32,
    index_buffer_offset: i32,
}
