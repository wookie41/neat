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

PipelineLayoutRef :: common.Ref(PipelineLayoutResource)

//---------------------------------------------------------------------------//

InvalidPipelineLayoutRef := PipelineLayoutRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_PIPELINE_LAYOUT_REF_ARRAY: common.RefArray(PipelineLayoutResource)
@(private = "file")
G_PIPELINE_LAYOUT_RESOURCE_ARRAY: []PipelineLayoutResource

//---------------------------------------------------------------------------//

@(private)
init_pipeline_layouts :: proc() {
	G_PIPELINE_LAYOUT_REF_ARRAY = common.ref_array_create(
		PipelineLayoutResource,
		MAX_PIPELINE_LAYOUTS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_PIPELINE_LAYOUT_RESOURCE_ARRAY = make(
		[]PipelineLayoutResource,
		MAX_PIPELINE_LAYOUTS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_pipeline_layouts()
}

//---------------------------------------------------------------------------//

allocate_pipeline_layout_ref :: proc(p_name: common.Name) -> PipelineLayoutRef {
	ref := PipelineLayoutRef(
		common.ref_create(PipelineLayoutResource, &G_PIPELINE_LAYOUT_REF_ARRAY, p_name),
	)
	get_pipeline_layout(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> bool {
	pipeline_layout := get_pipeline_layout(p_ref)

	if backend_create_pipeline_layout(p_ref, pipeline_layout) == false {
		common.ref_free(&G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_pipeline_layout :: proc(p_ref: PipelineLayoutRef) -> ^PipelineLayoutResource {
	return &G_PIPELINE_LAYOUT_RESOURCE_ARRAY[common.ref_get_idx(&G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

destroy_pipeline_layout :: proc(p_ref: PipelineLayoutRef) {
	pipeline_layout := get_pipeline_layout(p_ref)
	backend_destroy_pipeline_layout(pipeline_layout)
	common.ref_free(&G_PIPELINE_LAYOUT_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//
