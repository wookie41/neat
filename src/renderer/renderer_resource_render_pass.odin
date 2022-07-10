package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"

//---------------------------------------------------------------------------//

RenderPassDesc :: struct {
    name: common.Name,
    vert_shader: ShaderRef,
    frag_shader: ShaderRef,
    uniform_per_frame: BufferRef,
    uniform_per_view: BufferRef,
    univorm_per_instance: BufferRef,
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

init_render_passes :: proc() {
    G_RENDER_PASS_REF_ARRAY = create_ref_array(.RENDER_PASS, MAX_RENDER_PASSES)
	G_RENDER_PASS_RESOURCES = make([]RenderPassResource, MAX_RENDER_PASSES)
    backend_init_render_passes()
}

//---------------------------------------------------------------------------//

RenderPassResource :: struct {
	using backend_render_pass: BackendRenderPassResource,
    desc: RenderPassDesc,
}

//---------------------------------------------------------------------------//

RenderPassRef :: distinct Ref

//---------------------------------------------------------------------------//

InvalidRenderPassRef := RenderPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private="file")
G_RENDER_PASS_RESOURCES: []RenderPassResource

//---------------------------------------------------------------------------//

@(private="file")
G_RENDER_PASS_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

create_render_pass :: proc(
	p_render_pass_desc: RenderPassDesc,
) -> RenderPassRef {
	ref := RenderPassRef(create_ref(&G_RENDER_PASS_REF_ARRAY, p_render_pass_desc.name))
	idx := get_ref_idx(ref)
	render_pass := &G_RENDER_PASS_RESOURCES[idx]

	if backend_create_render_pass(
		p_render_pass_desc,
		render_pass,
	) == false {
        free_ref(&G_RENDER_PASS_REF_ARRAY, ref)
        return InvalidRenderPassRef
    }

    return ref
}

//---------------------------------------------------------------------------//

get_render_pass :: proc(p_ref: RenderPassRef) -> ^RenderPassResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_RENDER_PASS_RESOURCES)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_RENDER_PASS_REF_ARRAY.generations[idx])

	return &G_RENDER_PASS_RESOURCES[idx]
}

//---------------------------------------------------------------------------//
