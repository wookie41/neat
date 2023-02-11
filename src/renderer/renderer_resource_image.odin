package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:math/linalg/glsl"

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
G_IMAGE_REF_ARRAY: RefArray(ImageResource)

//---------------------------------------------------------------------------//

ImageRef :: Ref(ImageResource)

//---------------------------------------------------------------------------//

InvalidImageRef := ImageRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

ImageAspectFlagBits :: enum u8 {
	Color,
	Depth,
	Stencil,
}

//---------------------------------------------------------------------------//

ImageAspectFlags :: distinct bit_set[ImageAspectFlagBits;u8]

//---------------------------------------------------------------------------//

G_IMAGE_TYPE_NAME_MAPPING := map[string]ImageType {
	"2D" = .OneDimensional,
	"3D" = .ThreeDimensional,
}

//---------------------------------------------------------------------------//

ImageType :: enum u8 {
	OneDimensional,
	TwoDimensional,
	ThreeDimensional,
}

//---------------------------------------------------------------------------//

@(private)
G_IMAGE_FORMAT_NAME_MAPPING := map[string]ImageFormat {
	"Depth32SFloat" = .Depth32SFloat,
	"R32UInt"       = .R32UInt,
	"R32Int"        = .R32Int,
	"R32SFloat"     = .R32SFloat,
	"RG32UInt"      = .RG32UInt,
	"RG32Int"       = .RG32Int,
	"RG32SFloat"    = .RG32SFloat,
	"RGB32UInt"     = .RGB32UInt,
	"RGB32Int"      = .RGB32Int,
	"RGB32SFloat"   = .RGB32SFloat,
	"RGBA32UInt"    = .RGBA32UInt,
	"RGBA32Int"     = .RGBA32Int,
	"RGBA32SFloat"  = .RGBA32SFloat,
	"RGBA8_SRGB"    = .RGBA8_SRGB,
	"BGRA8_SRGB"    = .BGRA8_SRGB,
}

//---------------------------------------------------------------------------//

ImageFormat :: enum u16 {
	//---------------------//
	DepthFormatsStart,

	//---------------------//
	DepthStencilFormatsStart,
	DepthStencilFormatsEnd,
	//---------------------//
	Depth32SFloat,
	DepthFormatsEnd,

	//---------------------//
	ColorFormatsStart,
	RFormatsStart,
	R32UInt,
	R32Int,
	R32SFloat,
	RFormatsEnd,
	RGFormatsStart,
	RG32UInt,
	RG32Int,
	RG32SFloat,
	RGFormatsEnd,
	RGBFormatsStart,
	RGB32UInt,
	RGB32Int,
	RGB32SFloat,
	RGBFormatsEnd,
	RGBAFormatsStart,
	RGBA32UInt,
	RGBA32Int,
	RGBA32SFloat,
	R11G11B10,
	RGBAFormatsEnd,
	SRGB_FormatsStart,
	RGBA8_SRGB,
	BGRA8_SRGB,
	SRGB_FormatsEnd,
	ColorFormatsEnd,
	//---------------------//
}

//---------------------------------------------------------------------------//

ImageDescFlagBits :: enum u8 {
	Storage,
	SwapImage,
}
ImageDescFlags :: distinct bit_set[ImageDescFlagBits;u8]

//---------------------------------------------------------------------------//

ImageSampleFlagBits :: enum u8 {
	_1,
	_2,
	_4,
	_8,
	_16,
	_32,
	_64,
}
ImageSampleCountFlags :: distinct bit_set[ImageSampleFlagBits;u8]

//---------------------------------------------------------------------------//

ImageDesc :: struct {
	name:               common.Name,
	type:               ImageType,
	format:             ImageFormat,
	mip_count:          u8,
	data_per_mip:       [][]byte,
	dimensions:         glsl.uvec3,
	flags:              ImageDescFlags,
	sample_count_flags: ImageSampleCountFlags,
}

//---------------------------------------------------------------------------//

ImageResource :: struct {
	using backend_image: BackendImageResource,
	desc:                ImageDesc,
	bindless_idx:        u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	next_bindless_idx:     u32,
	free_bindless_indices: [dynamic]u32,
}

//---------------------------------------------------------------------------//


@(private)
TextureCopy :: struct {
	buffer:             BufferRef,
	image:              ImageRef,
	// offsets at which data for each mip is stored in the buffer
	mip_buffer_offsets: []u32,
}

//---------------------------------------------------------------------------//

@(private)
init_images :: proc() {
	G_IMAGE_REF_ARRAY = create_ref_array(ImageResource, MAX_IMAGES)
	INTERNAL.next_bindless_idx = 0
	INTERNAL.free_bindless_indices = make(
		[dynamic]u32,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	backend_init_images()
}

//---------------------------------------------------------------------------//

allocate_image_ref :: proc(p_name: common.Name) -> ImageRef {
	ref := ImageRef(create_ref(ImageResource, &G_IMAGE_REF_ARRAY, p_name))
	get_image(ref).desc.name = p_name
	return ref
}

/** Creates an image that can later be used as a sampled image inside a shader */
create_texture_image :: proc(p_ref: ImageRef) -> bool {
	image := get_image(p_ref)

	if len(INTERNAL.free_bindless_indices) > 0 {
		image.bindless_idx = pop(&INTERNAL.free_bindless_indices)
	} else {
		image.bindless_idx = INTERNAL.next_bindless_idx
		INTERNAL.next_bindless_idx += 1
	}

	assert(
		image.desc.format > .ColorFormatsStart && image.desc.format < .ColorFormatsEnd,
	)

	if backend_create_texture_image(p_ref, image) == false {
		free_ref(ImageResource, &G_IMAGE_REF_ARRAY, p_ref)
		return false
	}

	return true
}

create_depth_buffer :: proc(
	p_name: common.Name,
	p_depth_buffer_desc: ImageDesc,
) -> ImageRef {
	ref := allocate_image_ref(p_name)
	image := &G_IMAGE_REF_ARRAY.resource_array[get_ref_idx(ref)]
	image.desc = p_depth_buffer_desc

	if backend_create_depth_buffer(p_name, p_depth_buffer_desc, ref, image) == false {
		free_ref(ImageResource, &G_IMAGE_REF_ARRAY, ref)
		return InvalidImageRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_image :: proc(p_ref: ImageRef) -> ^ImageResource {
	return get_resource(ImageResource, &G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

create_swap_images :: #force_inline proc() {
	backend_create_swap_images()
}

//---------------------------------------------------------------------------//

destroy_image :: proc(p_ref: ImageRef) {
	image := get_image(p_ref)
	if image.bindless_idx != c.UINT32_MAX {
		append(&INTERNAL.free_bindless_indices, image.bindless_idx)
	}
	backend_destroy_image(image)
	free_ref(ImageResource, &G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_bindless_array_and_immutable_sampler :: #force_inline proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_layout_ref: PipelineLayoutRef,
	p_bind_point: PipelineType,
	p_target: u32,
) {

	backend_bind_bindless_array_and_immutable_sampler(
		get_command_buffer(p_cmd_buff_ref),
		get_pipeline_layout(p_pipeline_layout_ref),
		p_bind_point,
		p_target,
	)
}

//---------------------------------------------------------------------------//

update_images :: #force_inline proc(p_dt: f32) {
	backend_update_images(p_dt)
}

//---------------------------------------------------------------------------//
