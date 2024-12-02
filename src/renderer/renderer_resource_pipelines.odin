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
	Empty,
	Mesh,
}

//---------------------------------------------------------------------------//

PrimitiveType :: enum {
	TriangleList,
}

//---------------------------------------------------------------------------//

RasterizerType :: enum {
	Default,
	Shadows,
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

PushConstantDesc :: struct {
	offset_in_bytes: u32,
	size_in_bytes:   u32,
	shader_stages:   ShaderStageFlags,
}

//---------------------------------------------------------------------------//

GraphicsPipelineDesc :: struct {
	name:                   common.Name,
	render_pass_ref:        RenderPassRef,
	bind_group_layout_refs: []BindGroupLayoutRef,
	vert_shader_ref:        ShaderRef,
	frag_shader_ref:        ShaderRef,
	vertex_layout:          VertexLayout,
	push_constants:         []PushConstantDesc,
}

//---------------------------------------------------------------------------//

GraphicsPipelineResource :: struct {
	desc: GraphicsPipelineDesc,
}

//---------------------------------------------------------------------------//

GraphicsPipelineRef :: common.Ref(GraphicsPipelineResource)

//---------------------------------------------------------------------------//

InvalidGraphicsPipelineRef := GraphicsPipelineRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

ComputePipelineDesc :: struct {
	name:                   common.Name,
	bind_group_layout_refs: []BindGroupLayoutRef,
	compute_shader_ref:     ShaderRef,
	push_constants:         []PushConstantDesc,
}

//---------------------------------------------------------------------------//

ComputePipelineResource :: struct {
	desc: ComputePipelineDesc,
}

//---------------------------------------------------------------------------//

ComputePipelineRef :: common.Ref(ComputePipelineResource)

//---------------------------------------------------------------------------//

InvalidComputePipelineRef := ComputePipelineRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

PipelineStageFlagBits :: enum u16 {
	TopOfPipe,
	DrawIndirect,
	VertexInput,
	VertexShader,
	GeometryShader,
	PixelShader,
	EarlyPixelTests,
	LatePixelTests,
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

PipelineType :: enum u8 {
	Graphics,
	Compute,
}

//---------------------------------------------------------------------------//

@(private)
pipelines_init :: proc() -> bool {
	// Graphics pipelines
	g_resource_refs.graphics_pipelines = common.ref_array_create(
		GraphicsPipelineResource,
		MAX_GRAPHICS_PIPELINES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.graphics_pipelines = make_soa(
		#soa[]GraphicsPipelineResource,
		MAX_GRAPHICS_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_graphics_pipelines = make_soa(
		#soa[]BackendGraphicsPipelineResource,
		MAX_GRAPHICS_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Compute pipelines
	g_resource_refs.compute_pipelines = common.ref_array_create(
		ComputePipelineResource,
		MAX_COMPUTE_PIPELINES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.compute_pipelines = make_soa(
		#soa[]ComputePipelineResource,
		MAX_COMPUTE_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_compute_pipelines = make_soa(
		#soa[]BackendComputePipelineResource,
		MAX_COMPUTE_PIPELINES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	backend_pipelines_init() or_return

	return true
}

@(private)
pipelines_update :: proc() {
	backend_pipelines_update()
}
//---------------------------------------------------------------------------//

@(private)
pipelines_deinit :: proc() {
	backend_pipelines_deinit()
}

//---------------------------------------------------------------------------//

graphics_pipeline_allocate_ref :: proc(
	p_name: common.Name,
	p_bind_group_layouts_count: u32,
	p_push_constants_count: u32,
) -> GraphicsPipelineRef {
	ref := GraphicsPipelineRef(
		common.ref_create(GraphicsPipelineResource, &g_resource_refs.graphics_pipelines, p_name),
	)
	pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(ref)]
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

//---------------------------------------------------------------------------//

graphics_pipeline_create :: proc(p_ref: GraphicsPipelineRef) -> bool {
	if backend_graphics_pipeline_create(p_ref) == false {
		graphics_pipeline_destroy(p_ref)
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

get_graphics_pipeline_idx :: #force_inline proc(p_ref: GraphicsPipelineRef) -> u32 {
	return common.ref_get_idx(&g_resource_refs.graphics_pipelines, p_ref)
}

//---------------------------------------------------------------------------//

graphics_pipeline_destroy :: proc(p_ref: GraphicsPipelineRef) {
	pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(p_ref)]

	delete(pipeline.desc.bind_group_layout_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.bind_group_layout_refs = nil

	delete(pipeline.desc.push_constants, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.push_constants = nil

	backend_graphics_pipeline_destroy(p_ref)
}

//---------------------------------------------------------------------------//

graphics_pipeline_bind :: proc(
	p_pipeline_ref: GraphicsPipelineRef,
	p_cmd_buff_ref: CommandBufferRef,
) {
	backend_graphics_pipeline_bind(p_pipeline_ref, p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//

compute_pipeline_allocate_ref :: proc(
	p_name: common.Name,
	p_bind_group_layouts_count: u32,
	p_push_constants_count: u32,
) -> ComputePipelineRef {
	ref := ComputePipelineRef(
		common.ref_create(ComputePipelineResource, &g_resource_refs.compute_pipelines, p_name),
	)
	pipeline := &g_resources.compute_pipelines[get_compute_pipeline_idx(ref)]
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

//---------------------------------------------------------------------------//

compute_pipeline_create :: proc(p_ref: ComputePipelineRef) -> bool {
	if backend_compute_pipeline_create(p_ref) == false {
		compute_pipeline_destroy(p_ref)
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

get_compute_pipeline_idx :: #force_inline proc(p_ref: ComputePipelineRef) -> u32 {
	return common.ref_get_idx(&g_resource_refs.compute_pipelines, p_ref)
}

//---------------------------------------------------------------------------//

compute_pipeline_destroy :: proc(p_ref: ComputePipelineRef) {
	pipeline := &g_resources.compute_pipelines[get_compute_pipeline_idx(p_ref)]

	delete(pipeline.desc.bind_group_layout_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.bind_group_layout_refs = nil

	delete(pipeline.desc.push_constants, G_RENDERER_ALLOCATORS.resource_allocator)
	pipeline.desc.push_constants = nil

	backend_compute_pipeline_destroy(p_ref)
}

//---------------------------------------------------------------------------//

compute_pipeline_bind :: proc(
	p_pipeline_ref: ComputePipelineRef,
	p_cmd_buff_ref: CommandBufferRef,
) {
	backend_compute_pipeline_bind(p_pipeline_ref, p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//

graphics_pipeline_reset :: proc(p_ref: GraphicsPipelineRef) {
	backend_graphics_pipeline_reset(p_ref)
}

//---------------------------------------------------------------------------//

compute_pipeline_reset :: proc(p_ref: ComputePipelineRef) {
	backend_compute_pipeline_reset(p_ref)
}

//---------------------------------------------------------------------------//
