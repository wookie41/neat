package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:math/linalg/glsl"

import "../common"

//---------------------------------------------------------------------------//

ImageResource :: struct {
	using backend_layout: BackendImageResource,
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

@(private)
init_images :: proc() {
	G_IMAGE_REF_ARRAY = create_ref_array(.PIPELINE_LAYOUT, MAX_PIPELINE_LAYOUTS)
	G_IMAGE_RESOURCES = make([]ImageResource, MAX_PIPELINE_LAYOUTS)
}

//---------------------------------------------------------------------------//

ImageType :: enum u8
{
	ONE_DIMENSTIONAL,
	TWO_DIMENSTIONAL,
	THREE_DIMENSTIONAL,
}

//---------------------------------------------------------------------------//

ImageFormat :: enum u16
{
	DEPTH_32_SFLOAT,
}

//---------------------------------------------------------------------------//

ImageDesc :: struct 
{
	type: ImageType,
	format: ImageFormat,
	mip_count: u8,
	layer_count: u8,
	dimensions: glsl.uvec3,
}

//---------------------------------------------------------------------------//

create_image :: proc(p_name: common.Name, p_image_desc: ImageDesc) -> ImageRef {
	ref := ImageRef(create_ref(&G_IMAGE_REF_ARRAY, p_name))
	idx := get_ref_idx(ref)
	image := &G_IMAGE_RESOURCES[idx]

	image.desc = p_image_desc

	backend_create_image(image, p_name, p_image_desc)

    return ref
}

//---------------------------------------------------------------------------//