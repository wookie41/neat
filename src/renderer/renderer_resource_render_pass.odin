package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

RenderPassDesc :: struct {
	name:                     common.Name,
	vert_shader:              ShaderRef,
	frag_shader:              ShaderRef,
	uniform_per_frame:        BufferRef,
	uniform_per_view:         BufferRef,
	univorm_per_instance:     BufferRef,
	vertex_layout:            VertexLayout,
	primitive_type:           PrimitiveType,
	resterizer_type:          RasterizerType,
	multisampling_type:       MultisamplingType,
	depth_stencil_type:       DepthStencilType,
	color_attachment_formats: map[common.Name]ImageFormat,
	color_blend_types:        []ColorBlendType,
	depth_format:             ImageFormat,
}

//---------------------------------------------------------------------------//

RenderPassResource :: struct {
	using backend_render_pass: BackendRenderPassResource,
	desc:                      RenderPassDesc,
	pipeline:                  PipelineRef,
}

//---------------------------------------------------------------------------//

RenderPassRef :: distinct Ref

//---------------------------------------------------------------------------//

InvalidRenderPassRef := RenderPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_RESOURCES: []RenderPassResource

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

ColorAttachmentInfoFlagBits :: enum u8 {
	Clear,
}

ColorAttachmentFlags :: distinct bit_set[ColorAttachmentInfoFlagBits;u8]

//---------------------------------------------------------------------------//

ColorAttachmentInfo :: struct {
	flags:           ColorAttachmentInfoFlags,
	clear_value:     glsl.vec4,
	image_ref:       ImageRef,
	image_mip_level: u8,
}
//---------------------------------------------------------------------------//

RenderPassBeginInfo :: struct {
	color_attachments: map[common.Name]ColorAttachmentInfo,
	depth_attachment:  ImageRef,
}

//---------------------------------------------------------------------------//

@(private)
init_render_passes :: proc() {
	G_RENDER_PASS_REF_ARRAY = create_ref_array(.RENDER_PASS, MAX_RENDER_PASSES)
	G_RENDER_PASS_RESOURCES = make([]RenderPassResource, MAX_RENDER_PASSES)
	backend_init_render_passes()
}

//---------------------------------------------------------------------------//

@(private)
create_render_pass :: proc(p_render_pass_desc: RenderPassDesc) -> RenderPassRef {
	ref := RenderPassRef(create_ref(&G_RENDER_PASS_REF_ARRAY, p_render_pass_desc.name))
	idx := get_ref_idx(ref)
	render_pass := &G_RENDER_PASS_RESOURCES[idx]

	if backend_create_render_pass(p_render_pass_desc, render_pass) == false {
		free_ref(&G_RENDER_PASS_REF_ARRAY, ref)
		return InvalidRenderPassRef
	}

	return ref
}

//---------------------------------------------------------------------------//

@(private)
get_render_pass :: proc(p_ref: RenderPassRef) -> ^RenderPassResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_RENDER_PASS_RESOURCES)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_RENDER_PASS_REF_ARRAY.generations[idx])

	return &G_RENDER_PASS_RESOURCES[idx]
}

begin_render_pass :: #force_inline proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
	p_begin_info: RenderPassBeginInfo,
) {
	backend_begin_render_pass(p_render_pass_ref, p_cmd_buff_ref, p_begin_info)
}

//---------------------------------------------------------------------------//
