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


//---------------------------------------------------------------------------//

PipelineDesc :: struct {
	name:               common.Name,
	vert_shader:        ShaderRef,
	frag_shader:        ShaderRef,
	vertex_layout:      VertexLayout,
	primitive_type:     PrimitiveType,
	resterizer_type:    RasterizerType,
	multisampling_type: MultisamplingType,
	depth_stencil_type: DepthStencilType,
	render_pass_layout: RenderPassLayout,
}

//---------------------------------------------------------------------------//

PipelineResource :: struct {
	using backend_pipeline: BackendPipelineResource,
	desc:                   PipelineDesc,
	pipeline_layout_ref:    PipelineLayoutRef,
}

//---------------------------------------------------------------------------//

PipelineRef :: Ref(PipelineResource)

//---------------------------------------------------------------------------//

InvalidPipelineRef := PipelineRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

PipelineStageFlagBits :: enum u16 {
	TopOfPipe,
	DrawIndirect,
	VertexInput,
	VertexShader,
	GeometryShader,
	FragmentShader,
	EarlyFragmentTests,
	LateFragmentTests,
	AttachmentOutput,
	ComputeShader,
	Transfer,
	BottomOfPipe,
	Host,
	AllGraphics,
	AllCompute,
}

PipelineStageFlags :: distinct bit_set[PipelineStageFlagBits;u16]

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

allocate_pipeline_ref :: proc(p_name: common.Name) -> PipelineRef {
	ref := PipelineRef(create_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, p_name))
	get_pipeline(ref).desc.name = p_name
	return ref
}

create_graphics_pipeline :: proc(p_ref: PipelineRef) -> bool {

	// @TODO Create a hash based on the description's hash

	pipeline := get_pipeline(p_ref)

	res := backend_create_graphics_pipeline(p_ref, pipeline)

	if res == false {
		log.warn("Failed to create pipeline")
		free_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_pipeline :: proc(p_ref: PipelineRef) -> ^PipelineResource {
	return get_resource(PipelineResource, &G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_pipeline :: proc(p_ref: PipelineRef) {
	pipeline := get_pipeline(p_ref)
	destroy_pipeline_layout(pipeline.pipeline_layout_ref)
	backend_destroy_pipeline(pipeline)
	free_ref(PipelineResource, &G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_pipeline :: proc(p_pipeline_ref: PipelineRef, p_cmd_buff_ref: CommandBufferRef) {
	backend_bind_pipeline(get_pipeline(p_pipeline_ref), get_command_buffer(p_cmd_buff_ref))
}

//---------------------------------------------------------------------------//
