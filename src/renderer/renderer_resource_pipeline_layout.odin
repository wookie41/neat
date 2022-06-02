package renderer

//---------------------------------------------------------------------------//

import "core:c"

import "../common"

//---------------------------------------------------------------------------//

PipelineType :: enum u8 {
	GRAPHICS,
	GRAPHICS_MATERIAL,
}

//---------------------------------------------------------------------------//

PipelineLayoutResource :: struct {
	using backend_layout: BackendPipelineLayoutResource,
}

//---------------------------------------------------------------------------//

PipelineLayoutRef :: distinct Ref

//---------------------------------------------------------------------------//

InvalidPipelineLayoutRef := PipelineLayoutRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private)
G_PIPELINE_LAYOUT_RESOURCES: []PipelineLayoutResource

//---------------------------------------------------------------------------//

@(private)
G_PIPELINE_LAYOUT_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

@(private)
init_pipeline_layouts :: proc() {
	G_PIPELINE_LAYOUT_REF_ARRAY = create_ref_array(.PIPELINE_LAYOUT, MAX_PIPELINE_LAYOUTS)
	G_PIPELINE_LAYOUT_RESOURCES = make([]PipelineLayoutResource, MAX_PIPELINE_LAYOUTS)
}

//---------------------------------------------------------------------------//

@(private)
create_graphics_pipeline_layout :: proc(
	p_layout_type: PipelineType,
	p_vert_shader_ref: ShaderRef,
	p_frag_shader_ref: ShaderRef,
) -> PipelineLayoutRef {
	ref := PipelineLayoutRef(create_ref(&G_PIPELINE_LAYOUT_REF_ARRAY, common.EMPTY_NAME))
	idx := get_ref_idx(ref)
	pipeline_layout := &G_PIPELINE_LAYOUT_RESOURCES[idx]

	backend_reflect_pipeline_layout(
		pipeline_layout,
		p_layout_type,
		p_vert_shader_ref,
		p_frag_shader_ref,
	)

    return ref
}

//---------------------------------------------------------------------------//