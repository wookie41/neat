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

RenderPassLayout :: struct {
	render_target_formats:     []ImageFormat,
	render_target_blend_types: []ColorBlendType,
	depth_format:              ImageFormat,
}

RenderPassDesc :: struct {
	name:       common.Name,
	layout:     RenderPassLayout,
	resolution: RenderPassResolution,
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
	target: ^RenderTarget,
}

//---------------------------------------------------------------------------//

RenderPassBeginInfo :: struct {
	render_targets_bindings: []RenderTargetBinding,
	depth_attachment:        ^DepthAttachment,
}

//---------------------------------------------------------------------------//

allocate_render_pass_ref :: proc(p_name: common.Name) -> RenderPassRef {
	ref := RenderPassRef(
		create_ref(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_name),
	)
	get_render_pass(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_pass :: proc(p_render_pass_ref: RenderPassRef) -> bool {
	render_pass := get_render_pass(p_render_pass_ref)
	if backend_create_render_pass(p_render_pass_ref, render_pass) == false {
		free_ref(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_render_pass_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_render_pass :: proc(p_ref: RenderPassRef) -> ^RenderPassResource {
	return get_resource(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_render_pass :: proc(p_ref: RenderPassRef) {
	render_pass := get_render_pass(p_ref)
	if len(render_pass.desc.layout.render_target_formats) > 0 {
		delete(
			render_pass.desc.layout.render_target_formats,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

	}
	if len(render_pass.desc.layout.render_target_blend_types) > 0 {
		delete(
			render_pass.desc.layout.render_target_blend_types,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	backend_destroy_render_pass(render_pass)
	free_ref(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_ref)
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

//---------------------------------------------------------------------------//
