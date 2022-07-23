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

PipelineLayoutRef :: Ref(PipelineLayoutResource)

//---------------------------------------------------------------------------//

InvalidPipelineLayoutRef := PipelineLayoutRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_PIPELINE_LAYOUT_REF_ARRAY: RefArray(PipelineLayoutResource)

//---------------------------------------------------------------------------//

@(private)
init_pipeline_layouts :: proc() {
	G_PIPELINE_LAYOUT_REF_ARRAY = create_ref_array(
		PipelineLayoutResource,
		MAX_PIPELINE_LAYOUTS,
	)
}

//---------------------------------------------------------------------------//

PipelineLayoutDesc :: struct {
	name:            common.Name,
	layout_type:     PipelineType,
	vert_shader_ref: ShaderRef,
	frag_shader_ref: ShaderRef,
}

//---------------------------------------------------------------------------//

create_graphics_pipeline_layout :: proc(
	p_pipeline_layout_desc: PipelineLayoutDesc,
) -> PipelineLayoutRef {
	ref := PipelineLayoutRef(
		create_ref(
			PipelineLayoutResource,
			&G_PIPELINE_LAYOUT_REF_ARRAY,
			p_pipeline_layout_desc.name,
		),
	)
	idx := get_ref_idx(ref)
	pipeline_layout := &G_PIPELINE_LAYOUT_REF_ARRAY.resource_array[idx]

	if backend_reflect_pipeline_layout(pipeline_layout, p_pipeline_layout_desc) == false {
		free_ref(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, ref)
		return InvalidPipelineLayoutRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> ^PipelineLayoutResource {
	return get_resource(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
	free_ref(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
	backend_destroy_pipeline_layout(p_ref)
}

//---------------------------------------------------------------------------//
