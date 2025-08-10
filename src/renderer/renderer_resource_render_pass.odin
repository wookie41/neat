package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"
import "core:strconv"
import "core:strings"

//---------------------------------------------------------------------------//

G_RASTERIZER_NAME_MAPPING := map[string]RasterizerType {
	"Default" = .Default,
	"Shadows" = .Shadows,
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
	resolution:         glsl.uvec2,
	derived_resolution: Resolution,
}

//---------------------------------------------------------------------------//

RenderPassFlagBits :: enum u32 {
	IsActive,
}

RenderPassFlags :: distinct bit_set[RenderPassFlagBits;u32]

//---------------------------------------------------------------------------//

RenderPassResource :: struct {
	desc:  RenderPassDesc,
	flags: RenderPassFlags,
}

//---------------------------------------------------------------------------//

RenderPassRef :: common.Ref(RenderPassResource)

//---------------------------------------------------------------------------//

InvalidRenderPassRef := RenderPassRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_REF_ARRAY: common.RefArray(RenderPassResource)

//---------------------------------------------------------------------------//

RenderPassImageInputFlagBits :: enum u8 {
	Storage,
}

RenderPassImageInputFlags :: distinct bit_set[RenderPassImageInputFlagBits;u8]

//---------------------------------------------------------------------------//

RenderPassImageInput :: struct {
	image_ref:         ImageRef,
	flags:             RenderPassImageInputFlags,
	base_mip:          u32,
	mip_count:         u32,
	base_array_layer:  u32,
	array_layer_count: u32,
}

//---------------------------------------------------------------------------//

RenderPassImageOutputFlagBits :: enum u8 {
	Clear,
}

//---------------------------------------------------------------------------//

RenderPassImageOutputFlags :: distinct bit_set[RenderPassImageOutputFlagBits;u8]

//---------------------------------------------------------------------------//

RenderPassImageOutput :: struct {
	image_ref:   ImageRef,
	flags:       RenderPassImageOutputFlags,
	mip:         u32,
	array_layer: u32,
	clear_color: glsl.vec4,
}

//---------------------------------------------------------------------------//

RenderPassBufferUsage :: enum u8 {
	Uniform,
	General,
}

//---------------------------------------------------------------------------//

RenderPassBufferInput :: struct {
	buffer_ref: BufferRef,
	offset:     u32,
	size:       u32,
	usage:      RenderPassBufferUsage,
}

//---------------------------------------------------------------------------//

RenderPassBufferOutput :: struct {
	buffer_ref:         BufferRef,
	offset:             u32,
	size:               u32,
	needs_read_barrier: bool,
}

//---------------------------------------------------------------------------//

RenderPassBindings :: struct {
	image_inputs:        []RenderPassImageInput,
	image_outputs:       []RenderPassImageOutput,
	// Global images are the ones declared in resouces.hlsli that are always bound
	// They're declared as inputs so that we can issue proper barriers 
	global_image_inputs: []RenderPassImageInput,
	buffer_inputs:       []RenderPassBufferInput,
	buffer_outputs:      []RenderPassBufferOutput,
}

//---------------------------------------------------------------------------//

RenderPassBeginInfo :: struct {
	bindings: RenderPassBindings,
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
	raster_type:          string `json:"rasterType"`,
	depth_test_read_only: bool `json:"depthTestReadOnly"`,
}

//---------------------------------------------------------------------------//


@(private)
render_pass_init :: proc() -> bool {
	G_RENDER_PASS_REF_ARRAY = common.ref_array_create(
		RenderPassResource,
		MAX_RENDER_PASSES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.render_passes = make_soa(
		#soa[]RenderPassResource,
		MAX_RENDER_PASSES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backrender_pass_endes = make_soa(
		#soa[]BackendRenderPassResource,
		MAX_RENDER_PASSES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backrender_pass_end_init()
	render_pass_load_passes_from_config_file() or_return
	return true
}

//---------------------------------------------------------------------------//


render_pass_allocate :: proc(
	p_name: common.Name,
	p_render_target_count: int,
) -> RenderPassRef {
	ref := RenderPassRef(common.ref_create(RenderPassResource, &G_RENDER_PASS_REF_ARRAY, p_name))
	g_resources.render_passes[render_pass_get_idx(ref)].desc.name = p_name

	render_pass := &g_resources.render_passes[render_pass_get_idx(ref)]
	render_pass.desc.layout.render_target_formats = make(
		[]ImageFormat,
		p_render_target_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	render_pass.desc.layout.render_target_blend_types = make(
		[]ColorBlendType,
		p_render_target_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)


	return ref
}

//---------------------------------------------------------------------------//

render_pass_create :: proc(p_render_pass_ref: RenderPassRef) -> bool {
	if backrender_pass_end_create(p_render_pass_ref) == false {
		render_pass_destroy(p_render_pass_ref)
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

render_pass_get_idx :: #force_inline proc(p_ref: RenderPassRef) -> u32 {
	return common.ref_get_idx(&G_RENDER_PASS_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

render_pass_destroy :: proc(p_ref: RenderPassRef) {
	render_pass := &g_resources.render_passes[render_pass_get_idx(p_ref)]
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
	backrender_pass_end_destroy(p_ref)
	common.ref_free(&G_RENDER_PASS_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

@(private)
render_pass_begin :: proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
	p_begin_info: ^RenderPassBeginInfo,
) {

	transition_render_pass_resources(p_begin_info.bindings, .Graphics)
	backrender_pass_end_begin(p_render_pass_ref, p_cmd_buff_ref, p_begin_info)
}

//---------------------------------------------------------------------------//

render_pass_end :: #force_inline proc(
	p_render_pass_ref: RenderPassRef,
	p_cmd_buff_ref: CommandBufferRef,
) {
	backend_render_pass_end(p_render_pass_ref, p_cmd_buff_ref)
}

//---------------------------------------------------------------------------//

@(private = "file")
render_pass_load_passes_from_config_file :: proc() -> bool {
	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE * 4)
	defer common.arena_delete(temp_arena)

	render_passes_config := "app_data/renderer/config/render_passes.json"
	render_passes_json_data, file_read_ok := os.read_entire_file(
		render_passes_config,
		temp_arena.allocator,
	)

	if file_read_ok == false {
		return false
	}

	// Parse the render passes config file
	render_passes: []RenderPassJSONEntry

	if err := json.unmarshal(
		render_passes_json_data,
		&render_passes,
		.JSON5,
		temp_arena.allocator,
	); err != nil {
		log.errorf("Failed to render passes shaders json: %s\n", err)
		return false
	}

	// Create render passes 
	for render_pass_entry in render_passes {
		render_pass_ref := render_pass_allocate(
			common.create_name(render_pass_entry.name),
			len(render_pass_entry.render_targets),
		)

		render_pass := &g_resources.render_passes[render_pass_get_idx(render_pass_ref)]

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

		if render_pass_entry.resolution in G_RESOLUTION_NAME_MAPPING {
			render_pass.desc.derived_resolution =
				G_RESOLUTION_NAME_MAPPING[render_pass_entry.resolution]
		} else {

			resolution_parts, error := strings.split(
				render_pass_entry.resolution,
				"x",
				temp_arena.allocator,
			)
			if error != nil {
				return false
			}

			render_pass.desc.resolution.x = u32(strconv.atoi(resolution_parts[0]))
			render_pass.desc.resolution.y = u32(strconv.atoi(resolution_parts[1]))
		}

		for render_target_entry, i in render_pass_entry.render_targets {
			assert(render_target_entry.format in G_IMAGE_FORMAT_NAME_MAPPING)

			render_pass.desc.layout.render_target_blend_types[i] = .Default
			if render_target_entry.blend_type in G_BLEND_TYPE_NAME_MAPPING {
				render_pass.desc.layout.render_target_blend_types[i] =
					G_BLEND_TYPE_NAME_MAPPING[render_target_entry.blend_type]
			}

			render_pass.desc.layout.render_target_formats[i] =
				G_IMAGE_FORMAT_NAME_MAPPING[render_target_entry.format]
		}

		if len(render_pass_entry.raster_type) == 0 {
			render_pass.desc.resterizer_type = .Default
		} else {
			assert(render_pass_entry.raster_type in G_RASTERIZER_NAME_MAPPING)
			render_pass.desc.resterizer_type =
				G_RASTERIZER_NAME_MAPPING[render_pass_entry.raster_type]
		}

		assert(render_pass_create(render_pass_ref))
	}

	return true
}

//--------------------------------------------------------------------------//

render_pass_find_by_name :: proc {
	render_pass_find_by_name_name,
	render_pass_find_by_name_str,
}

//--------------------------------------------------------------------------//

render_pass_find_by_name_name :: proc(p_name: common.Name) -> RenderPassRef {
	ref := common.ref_find_by_name(&G_RENDER_PASS_REF_ARRAY, p_name)
	if ref == InvalidRenderPassRef {
		return InvalidRenderPassRef
	}
	return RenderPassRef(ref)
}

//--------------------------------------------------------------------------//

render_pass_find_by_name_str :: proc(p_name: string) -> RenderPassRef {
	ref := common.ref_find_by_name(&G_RENDER_PASS_REF_ARRAY, common.create_name(p_name))
	if ref == InvalidRenderPassRef {
		return InvalidRenderPassRef
	}
	return RenderPassRef(ref)
}

//--------------------------------------------------------------------------//

render_pass_destroy_bindings :: proc(p_render_pass_bindings: RenderPassBindings) {
	if p_render_pass_bindings.image_inputs != nil {
		delete(p_render_pass_bindings.image_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	if p_render_pass_bindings.image_outputs != nil {
		delete(p_render_pass_bindings.image_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	if p_render_pass_bindings.buffer_inputs != nil {
		delete(p_render_pass_bindings.buffer_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	if p_render_pass_bindings.buffer_outputs != nil {
		delete(p_render_pass_bindings.buffer_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
}

//--------------------------------------------------------------------------//
