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

@(private="file")
G_PIPELINE_LAYOUT_RESOURCES: []PipelineLayoutResource

//---------------------------------------------------------------------------//

@(private="file")
G_PIPELINE_LAYOUT_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

@(private)
init_pipeline_layouts :: proc() {
	G_PIPELINE_LAYOUT_REF_ARRAY = create_ref_array(.PIPELINE_LAYOUT, MAX_PIPELINE_LAYOUTS)
	G_PIPELINE_LAYOUT_RESOURCES = make([]PipelineLayoutResource, MAX_PIPELINE_LAYOUTS)
}

//---------------------------------------------------------------------------//

PipelineLayoutDesc :: struct 
{
	layout_type: PipelineType,
	vert_shader_ref: ShaderRef,
	frag_shader_ref: ShaderRef,
}

//---------------------------------------------------------------------------//

create_graphics_pipeline_layout :: proc(
	p_pipeline_layout_desc: PipelineLayoutDesc,
) -> PipelineLayoutRef {
	ref := PipelineLayoutRef(create_ref(&G_PIPELINE_LAYOUT_REF_ARRAY, common.EMPTY_NAME))
	idx := get_ref_idx(ref)
	pipeline_layout := &G_PIPELINE_LAYOUT_RESOURCES[idx]

	backend_reflect_pipeline_layout(
		pipeline_layout,
		p_pipeline_layout_desc,
	)

    return ref
}

//---------------------------------------------------------------------------//

get_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> ^PipelineLayoutResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_PIPELINE_LAYOUT_RESOURCES)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_PIPELINE_LAYOUT_REF_ARRAY.generations[idx])

	return &G_PIPELINE_LAYOUT_RESOURCES[idx]
}

//---------------------------------------------------------------------------//