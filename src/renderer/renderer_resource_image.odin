package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:math/linalg/glsl"

import "../common"

//---------------------------------------------------------------------------//

ImageResource :: struct {
	using backend_image: BackendImageResource,
	desc: ImageDesc,
}

//---------------------------------------------------------------------------//

ImageRef :: distinct Ref

//---------------------------------------------------------------------------//

InvalidImageRef := ImageRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private="file")
G_IMAGE_RESOURCES: []ImageResource

//---------------------------------------------------------------------------//

@(private="file")
G_IMAGE_REF_ARRAY: RefArray

//---------------------------------------------------------------------------//

ImageAspectFlagBits :: enum u8 
{
	Color,
	Depth,
	Stencil,
}

//---------------------------------------------------------------------------//

ImageAspectFlags :: distinct bit_set[ImageAspectFlagBits;u8]

//---------------------------------------------------------------------------//

ImageSubresourceRange :: struct {
	aspect: ImageAspectFlags,
	base_layer: u8,
	layer_count: u8,
	mip_level: u8,
}

//---------------------------------------------------------------------------//

@(private)
init_images :: proc() {
	G_IMAGE_REF_ARRAY = create_ref_array(.PIPELINE_LAYOUT, MAX_PIPELINE_LAYOUTS)
	G_IMAGE_RESOURCES = make([]ImageResource, MAX_PIPELINE_LAYOUTS)
	backend_init_images()
}

//---------------------------------------------------------------------------//

ImageType :: enum u8
{
	OneDimensional,
	TwoDimensional,
	ThreeDimensional,
}

//---------------------------------------------------------------------------//

ImageFormat :: enum u16
{
	DepthFormatsStart,
	Depth32SFloat,
	DepthFormatsEnd,
	ColorFormatsStart,
	ColorFormatsEnd,
}

//---------------------------------------------------------------------------//

ImageDescFlagBits :: enum u8
{
	Storage,
}
ImageDescFlags :: distinct bit_set[ImageDescFlagBits;u8]

//---------------------------------------------------------------------------//

ImageSampleFlagBits :: enum u8
{
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

ImageDesc :: struct 
{
	type: ImageType,
	format: ImageFormat,
	mip_count: u8,
	layer_count: u8,
	dimensions: glsl.uvec3,
	flags: ImageDescFlags,
	data: [][][]u8, // layer, mip
	sample_count_flags: ImageSampleCountFlags,
}

//---------------------------------------------------------------------------//

create_image :: proc(p_name: common.Name, p_image_desc: ImageDesc) -> ImageRef {
	ref := ImageRef(create_ref(&G_IMAGE_REF_ARRAY, p_name))
	idx := get_ref_idx(ref)
	image := &G_IMAGE_RESOURCES[idx]

	image.desc = p_image_desc

	backend_create_image(p_name, p_image_desc, ref, image)

    return ref
}

//---------------------------------------------------------------------------//

get_image :: proc(p_ref: ImageRef) -> ^ImageResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_IMAGE_RESOURCES)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_IMAGE_REF_ARRAY.generations[idx])

	return &G_IMAGE_RESOURCES[idx]
}

//---------------------------------------------------------------------------//
