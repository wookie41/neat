package renderer

//---------------------------------------------------------------------------//

import "../common"

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
	queue:     DeviceQueueType,
	flags:     ImageMemoryBarrierFlags,
}

//---------------------------------------------------------------------------//

@(private)
transition_binding_resources :: proc(
	p_bindings: []Binding,
	p_pipeline_type: PipelineType,
	p_async_compute: bool = false,
) {
	backend_transition_binding_resources(p_bindings, p_pipeline_type, p_async_compute)
}

//---------------------------------------------------------------------------//

@(private)
transition_render_outputs :: proc(p_render_outputs: []RenderPassOutput) {
	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	output_image_bindings := make([]Binding, len(p_render_outputs), temp_arena.allocator)

	for output_image, i in p_render_outputs {
		output_image_binding_flags := OutputImageBindingFlags{}
		if .Clear in output_image.flags {
			output_image_binding_flags += {.Clear}
		}

		output_image_bindings[i] = OutputImageBinding {
			image_ref   = output_image.image_ref,
			base_mip    = output_image.mip,
			mip_count   = 1,
			array_layer = output_image.array_layer,
			clear_color = output_image.clear_color,
			flags       = output_image_binding_flags,
		}
	}


	backend_transition_binding_resources(output_image_bindings, .Graphics, false)
}

//---------------------------------------------------------------------------//
