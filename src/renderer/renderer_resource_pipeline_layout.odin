package renderer

//---------------------------------------------------------------------------//

import "core:c"

import "../common"


//---------------------------------------------------------------------------//

PipelineType :: enum u8 {
	Graphics,
	Compute,
	Raytracing,
}

//---------------------------------------------------------------------------//

PipelineLayoutDesc :: struct {
	name:            common.Name,
	layout_type:     PipelineType,
	vert_shader_ref: ShaderRef,
	frag_shader_ref: ShaderRef,
}

//---------------------------------------------------------------------------//

PipelineLayoutResource :: struct {
	using backend_layout: BackendPipelineLayoutResource,
	desc:                 PipelineLayoutDesc,
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
	backend_init_pipeline_layouts()
}

//---------------------------------------------------------------------------//

allocate_pipeline_layout_ref :: proc(p_name: common.Name) -> PipelineLayoutRef {
	ref := PipelineLayoutRef(
		create_ref(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_name),
	)
	get_pipeline_layout(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> bool {
	pipeline_layout := get_pipeline_layout(p_ref)

	if backend_create_pipeline_layout(p_ref, pipeline_layout) == false {
		free_ref(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> ^PipelineLayoutResource {
	return get_resource(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
	pipeline_layout := get_pipeline_layout(p_ref)
	backend_destroy_pipeline_layout(pipeline_layout)
	free_ref(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//
