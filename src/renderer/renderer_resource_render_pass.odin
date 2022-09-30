package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"
import mem "core:mem"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

INTERNAL: struct {
	render_pass_instances:               []RenderPassInstance,
	num_allocated_render_pass_instances: u32,
}

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

Draw :: struct {
}

//---------------------------------------------------------------------------//

RenderPassInstance :: struct {
	
}

//---------------------------------------------------------------------------//

@(private)
init_render_passes :: proc() {
	G_RENDER_PASS_REF_ARRAY = create_ref_array(RenderPassResource, MAX_RENDER_PASSES)
	INTERNAL.render_pass_instances = make(
		[]RenderPassInstance,
		MAX_RENDER_PASS_INSTANCES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_render_passes()
}

//---------------------------------------------------------------------------//

render_pass_begin_frame :: proc() {
	INTERNAL.num_allocated_render_pass_instances = 0
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
) -> ^RenderPassInstance {
	render_pass_instance := &INTERNAL.render_pass_instances[INTERNAL.num_allocated_render_pass_instances]
	mem.zero_item(render_pass_instance)
	backend_begin_render_pass(p_render_pass_ref, p_cmd_buff_ref, p_begin_info, render_pass_instance)
	INTERNAL.num_allocated_render_pass_instances += 1
	return render_pass_instance
}

//---------------------------------------------------------------------------//

end_render_pass :: #force_inline proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
) {
	backend_end_render_pass(p_render_pass_ref, p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//


