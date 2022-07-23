package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:log"
import c "core:c"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

MeshVertexLayout :: struct {
	position: glsl.vec3,
	color:    glsl.vec3,
	uv:       glsl.vec2,
}

//---------------------------------------------------------------------------//

VertexLayout :: enum {
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
	name:                      common.Name,
	vert_shader:               ShaderRef,
	frag_shader:               ShaderRef,
	vertex_layout:             VertexLayout,
	primitive_type:            PrimitiveType,
	resterizer_type:           RasterizerType,
	multisampling_type:        MultisamplingType,
	depth_stencil_type:        DepthStencilType,
	render_target_formats:     []ImageFormat,
	render_target_blend_types: []ColorBlendType,
	depth_format:              ImageFormat,
}

//---------------------------------------------------------------------------//

PipelineResource :: struct {
	using backend_pipeline: BackendPipelineResource,
	desc:                   PipelineDesc,
	pipeline_layout:        PipelineLayoutRef,
}

//---------------------------------------------------------------------------//

PipelineRef :: Ref(PipelineResource)

//---------------------------------------------------------------------------//

InvalidPipelineRef := PipelineRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_PIPELINE_REF_ARRAY: RefArray(PipelineResource)

//---------------------------------------------------------------------------//

init_pipelines :: proc() {
	G_PIPELINE_REF_ARRAY = create_ref_array(PipelineResource, MAX_PIPELINES)
	backend_init_pipelines()
}

deinit_pipelines :: proc() {
	backend_deinit_pipelines()
}

//---------------------------------------------------------------------------//

create_graphics_pipeline :: proc(p_pipeline_desc: PipelineDesc) -> PipelineRef {

	// @TODO Create a hash based on the description's hash

	ref := PipelineRef(
		create_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, p_pipeline_desc.name),
	)
	idx := get_ref_idx(ref)
	pipeline := &G_PIPELINE_REF_ARRAY.resource_array[idx]
	pipeline.desc = p_pipeline_desc

	res := backend_create_graphics_pipeline(p_pipeline_desc, pipeline)

	if res == false {
		log.warn("Failed to create pipeline")
		free_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, ref)
		return InvalidPipelineRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_pipeline :: proc(p_ref: PipelineRef) -> ^PipelineResource {
	return get_resource(PipelineResource, &G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_pipeline :: proc(p_ref: PipelineRef) {
	pipeline := get_pipeline(p_ref)
	delete(pipeline.desc.render_target_formats, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(pipeline.desc.render_target_blend_types, G_RENDERER_ALLOCATORS.resource_allocator)
	backend_destroy_pipeline(pipeline)
	free_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//
