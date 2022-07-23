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

ImageType :: enum u8 {
	OneDimensional,
	TwoDimensional,
	ThreeDimensional,
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
	B8G8R8A8_SRGB,
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
	type:               ImageType,
	format:             ImageFormat,
	mip_count:          u8,
	data_per_mip:       [][]u8,
	dimensions:         glsl.uvec3,
	flags:              ImageDescFlags,
	sample_count_flags: ImageSampleCountFlags,
}

//---------------------------------------------------------------------------//

ImageResource :: struct {
	using backend_image: BackendImageResource,
	desc:                ImageDesc,
}

//---------------------------------------------------------------------------//

@(private)
init_images :: proc() {
	G_IMAGE_REF_ARRAY = create_ref_array(ImageResource, MAX_IMAGES)
	backend_init_images()
}

//---------------------------------------------------------------------------//

allocate_image_ref :: proc(p_name: common.Name) -> ImageRef {
	ref := ImageRef(create_ref(ImageResource, &G_IMAGE_REF_ARRAY, p_name))
	return ref
}

/** Creates an image that can later be used as a sampled image inside a shader */
create_texture_image :: proc(p_name: common.Name, p_image_desc: ImageDesc) -> ImageRef {
	ref := allocate_image_ref(p_name)
	image := &G_IMAGE_REF_ARRAY.resource_array[get_ref_idx(ref)]
	image.desc = p_image_desc

	if backend_create_texture_image(p_name, p_image_desc, ref, image) == false {
		free_ref(ImageResource, &G_IMAGE_REF_ARRAY, ref)
		return InvalidImageRef
	}

	return ref
}

create_depth_buffer :: proc(p_name: common.Name, p_depth_buffer_desc: ImageDesc) -> ImageRef {
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
	backend_destroy_image(image)
	free_ref(ImageResource, &G_IMAGE_REF_ARRAY, p_ref)
}