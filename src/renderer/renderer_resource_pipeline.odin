package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:log"
import c "core:c"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//
MeshVertexLayout :: struct {
	position: glsl.vec3,
	uv:       glsl.vec2,
	normal:   glsl.vec3,
	tangent:  glsl.vec3,
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

@(private)
G_BLEND_TYPE_NAME_MAPPING := map[string]ColorBlendType {
	"Default" = .Default,
}

//---------------------------------------------------------------------------//

PipelineDesc :: struct {
	name:            common.Name,
	render_pass_ref: RenderPassRef,
	vert_shader:     ShaderRef,
	frag_shader:     ShaderRef,
	vertex_layout:   VertexLayout,
}

//---------------------------------------------------------------------------//

PipelineResource :: struct {
	using backend_pipeline: BackendPipelineResource,
	desc:                   PipelineDesc,
	pipeline_layout_ref:    PipelineLayoutRef,
}

//---------------------------------------------------------------------------//

PipelineRef :: common.Ref(PipelineResource)

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
G_PIPELINE_REF_ARRAY: common.RefArray(PipelineResource)
@(private = "file")
G_PIPELINE_RESOURCE_ARRAY: []PipelineResource

//---------------------------------------------------------------------------//

init_pipelines :: proc() {
	G_PIPELINE_REF_ARRAY = common.ref_array_create(
		PipelineResource,
		MAX_PIPELINES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_PIPELINE_RESOURCE_ARRAY = make(
		[]PipelineResource,
		MAX_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_pipelines()
}

deinit_pipelines :: proc() {
	backend_deinit_pipelines()
}

//---------------------------------------------------------------------------//

allocate_pipeline_ref :: proc(p_name: common.Name) -> PipelineRef {
	ref := PipelineRef(common.ref_create(PipelineResource, &G_PIPELINE_REF_ARRAY, p_name))
	get_pipeline(ref).desc.name = p_name
	return ref
}

create_graphics_pipeline :: proc(p_ref: PipelineRef) -> bool {

	// @TODO Create a hash based on the description's hash

	pipeline := get_pipeline(p_ref)

	res := backend_create_graphics_pipeline(p_ref, pipeline)

	if res == false {
		log.warn("Failed to create pipeline")
		common.ref_free(&G_PIPELINE_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_pipeline :: proc(p_ref: PipelineRef) -> ^PipelineResource {
	return &G_PIPELINE_RESOURCE_ARRAY[common.ref_get_idx(&G_PIPELINE_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

destroy_pipeline :: proc(p_ref: PipelineRef) {
	pipeline := get_pipeline(p_ref)
	destroy_pipeline_layout(pipeline.pipeline_layout_ref)
	backend_destroy_pipeline(pipeline)
	common.ref_free(&G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_pipeline :: proc(p_pipeline_ref: PipelineRef, p_cmd_buff_ref: CommandBufferRef) {
	backend_bind_pipeline(get_pipeline(p_pipeline_ref), get_command_buffer(p_cmd_buff_ref))
}

//---------------------------------------------------------------------------//
