package renderer

//---------------------------------------------------------------------------//

ImageMemoryBarrierFlagBits :: enum u16 {
	VertexShaderSampleImage,
	PixelShaderSampleImage,
	ComputeShaderSampleImage,
	VertexShaderGeneralReadImage,
	PixelShaderGeneralImage,
	ComputeShaderGeneralImage,
	ColorAttachmentImage,
	DepthAttachmentImage,
	ComputeShaderStorageImage,
}

//---------------------------------------------------------------------------//

ImageMemoryBarrierFlags :: distinct bit_set[ImageMemoryBarrierFlagBits;u16]

//---------------------------------------------------------------------------//

ImageBarrier :: struct {
	image_ref: ImageRef,
	queue: DeviceQueueType,
	flags: ImageMemoryBarrierFlags,
}

//---------------------------------------------------------------------------//

@(private)
transition_render_pass_resources :: proc(
	p_bindings: RenderPassBindings,
    p_pipeline_type: PipelineType,
	p_async_compute: bool = false,
) {
	backend_transition_render_pass_resources(p_bindings, p_pipeline_type, p_async_compute)
}

//---------------------------------------------------------------------------//

@(private)
insert_barriers :: proc(p_cmd_buff_ref: CommandBufferRef, p_image_barriers: []ImageBarrier) {
	backend_insert_barriers(p_cmd_buff_ref, p_image_barriers)
}

//---------------------------------------------------------------------------//
