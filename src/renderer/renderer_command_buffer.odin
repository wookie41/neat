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

ImageCopyRegion :: struct {
	buffer_offset:     u32,
	subresource_range: ImageSubresourceRange,
}

//---------------------------------------------------------------------------//

BufferImageCopy :: struct {
	buffer:  BufferRef,
	image:   ImageRef,
	regions: []ImageCopyRegion,
}

//---------------------------------------------------------------------------//
