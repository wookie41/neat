package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

RenderPassResolution :: enum u8 {
	Full,
	Half,
	Quarter,
}

//---------------------------------------------------------------------------//

RenderTargetInfo :: struct {
	name:   common.Name,
	format: ImageFormat,
}

//---------------------------------------------------------------------------//

RenderPassDesc :: struct {
	name:                      common.Name,
	vert_shader:               ShaderRef,
	frag_shader:               ShaderRef,
	uniform_per_frame:         BufferRef, //@TODO
	uniform_per_view:          BufferRef, //@TODO
	univorm_per_instance:      BufferRef, //@TODO
	vertex_layout:             VertexLayout,
	primitive_type:            PrimitiveType,
	rasterizer_type:           RasterizerType,
	multisampling_type:        MultisamplingType,
	depth_stencil_type:        DepthStencilType,
	render_target_infos:       []RenderTargetInfo,
	render_target_blend_types: []ColorBlendType,
	depth_format:              ImageFormat,
	resolution:                RenderPassResolution,
}

//---------------------------------------------------------------------------//

RenderPassFlagBits :: enum u32 {
	IsActive,
}

RenderPassFlags :: distinct bit_set[RenderPassFlagBits;u32]

//---------------------------------------------------------------------------//

RenderPassResource :: struct {
	using backend_render_pass: BackendRenderPassResource,
	desc:                      RenderPassDesc,
	pipeline:                  PipelineRef,
	flags:                     RenderPassFlags,
}

//---------------------------------------------------------------------------//

RenderPassRef :: Ref(RenderPassResource)

//---------------------------------------------------------------------------//

InvalidRenderPassRef := RenderPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_REF_ARRAY: RefArray(RenderPassResource)

//---------------------------------------------------------------------------//

ColorAttachmentInfoFlagBits :: enum u8 {
	Clear,
}

ColorAttachmentFlags :: distinct bit_set[ColorAttachmentInfoFlagBits;u8]

//---------------------------------------------------------------------------//

RenderTargetUsage :: enum u8 {
	Undefined,
	SampledImage,
	Attachment,
}

//---------------------------------------------------------------------------//

RenderTargetFlagBits :: enum u8 {
	Clear,
}

RenderTargetFlags :: distinct bit_set[RenderTargetFlagBits;u8]

//---------------------------------------------------------------------------//

RenderTarget :: struct {
	clear_value:   glsl.vec4,
	image_ref:     ImageRef,
	image_mip:     i16,
	current_usage: RenderTargetUsage,
	flags:         RenderTargetFlags,
}

//---------------------------------------------------------------------------//

DepthAttachment :: struct {
	image: ImageRef,
	usage: RenderTargetUsage,
}

//---------------------------------------------------------------------------//

RenderTargetBinding :: struct {
	name:   common.Name,
	target: ^RenderTarget,
}

//---------------------------------------------------------------------------//

RenderPassBeginInfo :: struct {
	render_targets_bindings: []RenderTargetBinding,
	depth_attachment:        ^DepthAttachment,
}

//---------------------------------------------------------------------------//

@(private)
init_render_passes :: proc() {
	G_RENDER_PASS_REF_ARRAY = create_ref_array(RenderPassResource, MAX_RENDER_PASSES)
	backend_init_render_passes()
}

//---------------------------------------------------------------------------//

create_render_pass :: proc(p_render_pass_desc: RenderPassDesc) -> RenderPassRef {
	ref := RenderPassRef(
		create_ref(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_render_pass_desc.name),
	)
	idx := get_ref_idx(ref)
	render_pass := &G_RENDER_PASS_REF_ARRAY.resource_array[idx]
	render_pass.desc = p_render_pass_desc

	if backend_create_render_pass(p_render_pass_desc, render_pass) == false {
		free_ref(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, ref)
		return InvalidRenderPassRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_render_pass :: proc(p_ref: RenderPassRef) -> ^RenderPassResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_RENDER_PASS_REF_ARRAY.resource_array)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_RENDER_PASS_REF_ARRAY.generations[idx])

	return &G_RENDER_PASS_REF_ARRAY.resource_array[idx]
}

@(private)
begin_render_pass :: #force_inline proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
	p_begin_info: ^RenderPassBeginInfo,
) {
	backend_begin_render_pass(p_render_pass_ref, p_cmd_buff_ref, p_begin_info)
}

//---------------------------------------------------------------------------//

end_render_pass :: #force_inline proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
) {
	backend_end_render_pass(p_render_pass_ref, p_cmd_buff_ref)
}
