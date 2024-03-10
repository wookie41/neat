package renderer

//---------------------------------------------------------------------------//

@(private)
transition_resources :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_bindings: ^RenderPassBindings,
    p_pipeline_type: PipelineType,
) {
	backend_transition_resources(p_cmd_buff_ref, p_bindings, p_pipeline_type)
}

//---------------------------------------------------------------------------//
