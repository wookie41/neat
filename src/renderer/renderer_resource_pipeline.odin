package renderer

//---------------------------------------------------------------------------//

import "../common"
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

PipelineType :: enum u8 {
	Graphics,
	Compute,
	Raytracing,
}

//---------------------------------------------------------------------------//

PushConstantDesc :: struct {
	offset_in_bytes: u32,
	size_in_bytes:   u32,
	shader_stages:   ShaderStageFlags,
}

//---------------------------------------------------------------------------//

PipelineDesc :: struct {
	name:                   common.Name,
	render_pass_ref:        RenderPassRef,
	vert_shader_ref:        ShaderRef,
	bind_group_layout_refs: []BindGroupLayoutRef,
	frag_shader_ref:        ShaderRef,
	vertex_layout:          VertexLayout,
	push_constants:         []PushConstantDesc,
}

//---------------------------------------------------------------------------//

PipelineResource :: struct {
	desc: PipelineDesc,
	type: PipelineType,
}

//---------------------------------------------------------------------------//

PipelineRef :: common.Ref(PipelineResource)

//---------------------------------------------------------------------------//

InvalidPipelineRef := PipelineRef {
	ref = c.UINT32_MAX,
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

//---------------------------------------------------------------------------//

init_pipelines :: proc() -> bool {
	G_PIPELINE_REF_ARRAY = common.ref_array_create(
		PipelineResource,
		MAX_PIPELINES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.pipelines = make_soa(
		#soa[]PipelineResource,
		MAX_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_pipelines = make_soa(
		#soa[]BackendPipelineResource,
		MAX_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_pipelines() or_return

	return true
}

deinit_pipelines :: proc() {
	backend_deinit_pipelines()
}

//---------------------------------------------------------------------------//

allocate_pipeline_ref :: proc(
	p_name: common.Name,
	p_bind_group_layouts_count: u32,
	p_push_constants_count: u32,
) -> PipelineRef {
	ref := PipelineRef(common.ref_create(PipelineResource, &G_PIPELINE_REF_ARRAY, p_name))
	pipeline := &g_resources.pipelines[get_pipeline_idx(ref)]
	pipeline.desc.name = p_name
	pipeline.desc.bind_group_layout_refs = make(
		[]BindGroupLayoutRef,
		p_bind_group_layouts_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	pipeline.desc.push_constants = make(
		[]PushConstantDesc,
		p_push_constants_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	return ref
}

create_graphics_pipeline :: proc(p_ref: PipelineRef) -> bool {

	pipeline := &g_resources.pipelines[get_pipeline_idx(p_ref)]
	pipeline.type = .Graphics

	res := backend_create_graphics_pipeline(p_ref)

	if res == false {
		destroy_pipeline(p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_pipeline_idx :: #force_inline proc(p_ref: PipelineRef) -> u32 {
	return common.ref_get_idx(&G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_pipeline :: proc(p_ref: PipelineRef) {
	pipeline := &g_resources.pipelines[get_pipeline_idx(p_ref)]

	delete(pipeline.desc.bind_group_layout_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.bind_group_layout_refs = nil

	delete(pipeline.desc.push_constants, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.push_constants = nil

	backend_destroy_pipeline(p_ref)
	common.ref_free(&G_PIPELINE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_pipeline :: proc(p_pipeline_ref: PipelineRef, p_cmd_buff_ref: CommandBufferRef) {
	backend_bind_pipeline(p_pipeline_ref, p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//
