package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"

//---------------------------------------------------------------------------//

VertexLayout :: enum {
    // position
    // normal
    // uv
    Mesh,
}

//---------------------------------------------------------------------------//

PrimitiveType :: enum {
    TriangleList,
}

//---------------------------------------------------------------------------//

RasterizerType :: enum {
    Fill,
}

//---------------------------------------------------------------------------//

MultisamplingType :: enum {
    _1,
}

//---------------------------------------------------------------------------//

DepthStencilType :: enum {
    None,
    DepthTestWrite,
    DepthTestReadOnly,
}

//---------------------------------------------------------------------------//

ColorBlendType :: enum {
    Default,
}

//---------------------------------------------------------------------------//

PipelineDesc :: struct {
    name: common.Name,
    vert_shader: ShaderRef,
    frag_shader: ShaderRef,
    vertex_layout: VertexLayout,
    primitive_type: PrimitiveType,
    resterizer_type: RasterizerType,
    multisampling_type: MultisamplingType,
    depth_stencil_type: DepthStencilType,
    color_attachment_formats: []ImageFormat,
    color_blend_types: []ColorBlendType,
    depth_format: ImageFormat,
}

//---------------------------------------------------------------------------//

PipelineResource :: struct {
	using backend_pipeline: BackendPipelineResource,
    desc: PipelineDesc,
    pipeline_layout: PipelineLayoutRef,
}

//---------------------------------------------------------------------------//

PipelineRef :: distinct Ref

//---------------------------------------------------------------------------//

InvalidPipelineRef := PipelineRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private="file")
G_PIPELINE_RESOURCES: []PipelineResource

//---------------------------------------------------------------------------//

@(private="file")
G_PIPELINE_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

init_pipelines :: proc() {
    G_PIPELINE_REF_ARRAY = create_ref_array(.PIPELINE, MAX_PIPELINES)
	G_PIPELINE_RESOURCES = make([]PipelineResource, MAX_PIPELINES)
    backend_init_pipelines()
}

deinit_pipelines :: proc() {
    backend_deinit_pipelines()
}

//---------------------------------------------------------------------------//

create_pipeline :: proc(
	p_pipeline_desc: PipelineDesc,
) -> PipelineRef {
	ref := PipelineRef(create_ref(&G_PIPELINE_REF_ARRAY, p_pipeline_desc.name))
	idx := get_ref_idx(ref)
	pipeline := &G_PIPELINE_RESOURCES[idx]

	res := backend_create_pipeline(
		p_pipeline_desc,
		pipeline,
	)

    if res == false {
        free_ref(&G_PIPELINE_REF_ARRAY, ref)
        return InvalidPipelineRef
    }

    return ref
}

//---------------------------------------------------------------------------//

get_pipeline :: proc(p_ref: PipelineRef) -> ^PipelineResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_PIPELINE_RESOURCES)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_PIPELINE_REF_ARRAY.generations[idx])

	return &G_PIPELINE_RESOURCES[idx]
}

//---------------------------------------------------------------------------//
