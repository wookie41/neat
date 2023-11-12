package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:math/linalg/glsl"

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
G_IMAGE_REF_ARRAY: common.RefArray(ImageResource)

//---------------------------------------------------------------------------//

ImageRef :: common.Ref(ImageResource)

//---------------------------------------------------------------------------//

InvalidImageRef := ImageRef {
	ref = c.UINT32_MAX,
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
	CompressedFormatsStart,
	BC1_RGB_UNorm,
	BC1_RGB_SRGB,
	BC1_RGBA_UNorm,
	BC1_RGBA_SRGB,
	BC2_UNorm,
	BC2_SRGB,
	BC3_UNorm,
	BC3_SRGB,
	BC4_UNorm,
	BC4_SNorm,
	BC5_UNorm,
	BC5_SNorm,
	BC6H_UFloat,
	BC6H_SFloat,
	BC7_UNorm,
	BC7_SRGB,
	CompressedFormatsEnd,
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
	desc:         ImageDesc,
	bindless_idx: u32,
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
	buffer_ref:         BufferRef,
	image_ref:          ImageRef,
	// offsets at which data for each mip is stored in the buffer
	mip_buffer_offsets: []u32,
}
//---------------------------------------------------------------------------//

SamplerType :: enum {
	NearestClampToEdge,
	NearestClampToBorder,
	NearestRepeat,
	LinearClampToEdge,
	LinearClampToBorder,
	LinearRepeat,
}
//---------------------------------------------------------------------------//

@(private)
SamplerNames := []string{
	"NearestClampToEdge",
	"NearestClampToBorder",
	"NearestRepeat",
	"LinearClampToEdge",
	"LinearClampToBorder",
	"LinearRepeat",
}
//---------------------------------------------------------------------------//

@(private)
init_images :: proc() {
	G_IMAGE_REF_ARRAY = common.ref_array_create(
		ImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.images = make_soa(
		#soa[]ImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_images = make_soa(
		#soa[]BackendImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	INTERNAL.next_bindless_idx = 0
	INTERNAL.free_bindless_indices = make([dynamic]u32, G_RENDERER_ALLOCATORS.main_allocator)
	backend_init_images()
}

//---------------------------------------------------------------------------//

allocate_image_ref :: proc(p_name: common.Name) -> ImageRef {
	ref := ImageRef(common.ref_create(ImageResource, &G_IMAGE_REF_ARRAY, p_name))
	img_idx := get_image_idx(ref)
	g_resources.images[img_idx].desc.name = p_name
	return ref
}

/** Creates an image that can later be used as a sampled image inside a shader */
create_texture_image :: proc(p_ref: ImageRef) -> bool {

	image := &g_resources.images[get_image_idx(p_ref)]

	if len(INTERNAL.free_bindless_indices) > 0 {
		image.bindless_idx = pop(&INTERNAL.free_bindless_indices)
	} else {
		image.bindless_idx = INTERNAL.next_bindless_idx
		INTERNAL.next_bindless_idx += 1
	}

	assert(
		(image.desc.format > .ColorFormatsStart && image.desc.format < .ColorFormatsEnd) ||
		(image.desc.format > .CompressedFormatsStart && image.desc.format < .CompressedFormatsEnd),
	)

	if backend_create_texture_image(p_ref) == false {
		common.ref_free(&G_IMAGE_REF_ARRAY, p_ref)
		return false
	}

	return true
}

create_depth_buffer :: proc(p_name: common.Name, p_depth_buffer_desc: ImageDesc) -> ImageRef {
	ref := allocate_image_ref(p_name)
	image := &g_resources.images[get_image_idx(ref)]
	image.desc = p_depth_buffer_desc

	if backend_create_depth_buffer(p_name, p_depth_buffer_desc, ref) == false {
		common.ref_free(&G_IMAGE_REF_ARRAY, ref)
		return InvalidImageRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_image_idx :: #force_inline proc(p_ref: ImageRef) -> u32 {
	return common.ref_get_idx(&G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

create_swap_images :: #force_inline proc() {
	backend_create_swap_images()
}

//---------------------------------------------------------------------------//

destroy_image :: proc(p_ref: ImageRef) {
	image := &g_resources.images[get_image_idx(p_ref)]
	if image.bindless_idx != c.UINT32_MAX {
		append(&INTERNAL.free_bindless_indices, image.bindless_idx)
	}
	backend_destroy_image(p_ref)
	common.ref_free(&G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

batch_update_bindless_array_entries :: #force_inline proc() {
	backend_batch_update_bindless_array_entries()
}

//---------------------------------------------------------------------------//

find_image :: proc {
	find_image_by_name,
	find_image_by_str,
}

//---------------------------------------------------------------------------//

find_image_by_name :: proc(p_name: common.Name) -> ImageRef {
	ref := common.ref_find_by_name(&G_IMAGE_REF_ARRAY, p_name)
	if ref == InvalidImageRef {
		return InvalidImageRef
	}
	return ImageRef(ref)
}

//--------------------------------------------------------------------------//

find_image_by_str :: proc(p_str: string) -> ImageRef {
	return find_image_by_name(common.make_name(p_str))
}

//--------------------------------------------------------------------------//
