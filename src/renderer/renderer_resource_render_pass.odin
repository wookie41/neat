package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"
import "core:math/linalg/glsl"
import "core:encoding/json"
import "core:os"
import "core:log"

//---------------------------------------------------------------------------//

RenderPassResolution :: enum u8 {
	Full,
	Half,
	Quarter,
}

//---------------------------------------------------------------------------//

G_RESOLUTION_NAME_MAPPING := map[string]RenderPassResolution {
	"Full"    = .Full,
	"Half"    = .Half,
	"Quarter" = .Quarter,
}

//---------------------------------------------------------------------------//

G_RASTERIZER_NAME_MAPPING := map[string]RasterizerType {
	"Fill" = .Fill,
}

//---------------------------------------------------------------------------//

G_MULTISAMPLING_NAME_MAPPING := map[string]MultisamplingType {
	"1" = ._1,
}

//---------------------------------------------------------------------------//

G_PRIMITIVE_TYPE_NAME_MAPPING := map[string]PrimitiveType {
	"TriangleList" = .TriangleList,
}
//---------------------------------------------------------------------------//

RenderPassLayout :: struct {
	render_target_formats:     []ImageFormat,
	render_target_blend_types: []ColorBlendType,
	depth_format:              ImageFormat,
}

RenderPassDesc :: struct {
	name:               common.Name,
	layout:             RenderPassLayout,
	depth_stencil_type: DepthStencilType,
	primitive_type:     PrimitiveType,
	resterizer_type:    RasterizerType,
	multisampling_type: MultisamplingType,
	resolution:         RenderPassResolution,
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

RenderPassRef :: common.Ref(RenderPassResource)

//---------------------------------------------------------------------------//

InvalidRenderPassRef := RenderPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_REF_ARRAY: common.RefArray(RenderPassResource)
@(private = "file")
G_RENDER_PASS_RESOURCE_ARRAY: []RenderPassResource

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

RenderTargetJSONEntry :: struct {
	format:     string,
	blend_type: string `json:"blendType"`,
}

//---------------------------------------------------------------------------//

RenderPassJSONEntry :: struct {
	name:                 string,
	render_targets:       []RenderTargetJSONEntry `json:"renderTargets"`,
	depth_format:         string `json:"depthFormat"`,
	resolution:           string,
	depth_test_read_only: bool `json:"depthTestReadOnly"`,
}

//---------------------------------------------------------------------------//


@(private)
init_render_passes :: proc() -> bool {
	G_RENDER_PASS_REF_ARRAY = common.ref_array_create(
		RenderPassResource,
		MAX_RENDER_PASSES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_RENDER_PASS_RESOURCE_ARRAY = make(
		[]RenderPassResource,
		MAX_RENDER_PASSES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_render_passes()
	load_render_passes_from_config_file() or_return
	return true
}

//---------------------------------------------------------------------------//


allocate_render_pass_ref :: proc(p_name: common.Name) -> RenderPassRef {
	ref := RenderPassRef(common.ref_create(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_name))
	get_render_pass(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_pass :: proc(p_render_pass_ref: RenderPassRef) -> bool {
	render_pass := get_render_pass(p_render_pass_ref)
	if backend_create_render_pass(p_render_pass_ref, render_pass) == false {
		common.ref_free(&G_RENDER_PASS_REF_ARRAY, p_render_pass_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_render_pass :: proc(p_ref: RenderPassRef) -> ^RenderPassResource {
	return &G_RENDER_PASS_RESOURCE_ARRAY[common.ref_get_idx(&G_RENDER_PASS_REF_ARRAY, p_ref)]
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
	common.ref_free(&G_RENDER_PASS_REF_ARRAY, p_ref)
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

@(private = "file")
load_render_passes_from_config_file :: proc() -> bool {
	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	render_passes_config := "app_data/renderer/config/render_passes.json"
	render_passes_json_data, file_read_ok := os.read_entire_file(render_passes_config)

	if file_read_ok == false {
		return false
	}

	// Parse the render passes config file
	render_passes: []RenderPassJSONEntry

	if err := json.unmarshal(render_passes_json_data, &render_passes); err != nil {
		log.errorf("Failed to render passes shaders json: %s\n", err)
		return false
	}

	// Create render passes 
	for render_pass_entry in render_passes {
		render_pass_ref := allocate_render_pass_ref(common.create_name(render_pass_entry.name))

		render_pass := get_render_pass(render_pass_ref)

		// Check if this render pass has a depth test 
		if len(render_pass_entry.depth_format) > 0 {
			assert(render_pass_entry.depth_format in G_IMAGE_FORMAT_NAME_MAPPING)

			render_pass.desc.layout.depth_format =
				G_IMAGE_FORMAT_NAME_MAPPING[render_pass_entry.depth_format]

			if render_pass_entry.depth_test_read_only {
				render_pass.desc.depth_stencil_type = .DepthTestReadOnly
			} else {
				render_pass.desc.depth_stencil_type = .DepthTestWrite
			}

		} else {
			render_pass.desc.depth_stencil_type = .None
		}


		// Parse resolution
		assert(render_pass_entry.resolution in G_RESOLUTION_NAME_MAPPING)
		render_pass.desc.resolution = G_RESOLUTION_NAME_MAPPING[render_pass_entry.resolution]

		// Parse render targets
		assert(len(render_pass_entry.render_targets) > 0)
		render_pass.desc.layout.render_target_formats = make(
			[]ImageFormat,
			len(render_pass_entry.render_targets),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		render_pass.desc.layout.render_target_blend_types = make(
			[]ColorBlendType,
			len(render_pass_entry.render_targets),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for render_target_entry, i in render_pass_entry.render_targets {
			assert(render_target_entry.format in G_IMAGE_FORMAT_NAME_MAPPING)
			assert(render_target_entry.blend_type in G_BLEND_TYPE_NAME_MAPPING)

			render_pass.desc.layout.render_target_formats[i] =
				G_IMAGE_FORMAT_NAME_MAPPING[render_target_entry.format]
			render_pass.desc.layout.render_target_blend_types[i] =
				G_BLEND_TYPE_NAME_MAPPING[render_target_entry.blend_type]
		}

		// @TODO primitive typ, rasterizer overrides

		assert(create_render_pass(render_pass_ref))
	}

	return true
}

//--------------------------------------------------------------------------//

find_render_pass_by_name :: proc {
	find_render_pass_by_name_name,
	find_render_pass_by_name_str,
}

//--------------------------------------------------------------------------//

find_render_pass_by_name_name :: proc(p_name: common.Name) -> RenderPassRef {
	ref := common.ref_find_by_name(&G_RENDER_PASS_REF_ARRAY, p_name)
	if ref == InvalidRenderPassRef {
		return InvalidRenderPassRef
	}
	return RenderPassRef(ref)
}

//--------------------------------------------------------------------------//

find_render_pass_by_name_str :: proc(p_name: string) -> RenderPassRef {
	ref := common.ref_find_by_name(&G_RENDER_PASS_REF_ARRAY, common.make_name(p_name))
	if ref == InvalidRenderPassRef {
		return InvalidRenderPassRef
	}
	return RenderPassRef(ref)
}

//--------------------------------------------------------------------------//
