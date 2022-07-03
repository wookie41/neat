package renderer

CommandBufferHandle :: distinct u32

//---------------------------------------------------------------------------//

CommandBufferFlagBits :: enum u8 {
	Primary,
}

@(private)
CommandBufferFlags :: distinct bit_set[CommandBufferFlagBits;u8]

//---------------------------------------------------------------------------//

CommandBufferDesc :: struct {
	flags:  CommandBufferFlags,
	thread: u8,
	frame:  u8,
}

//---------------------------------------------------------------------------//

BufferImageCopy :: struct {
	buffer:            BufferRef,
	image:             ImageRef,
	buffer_offset:     u32,
	subresource_range: ImageSubresourceRange,
}

//---------------------------------------------------------------------------//
