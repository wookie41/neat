package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"
	import "../common"

	//---------------------------------------------------------------------------//

	BackendImageResource :: struct {}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_TYPE_MAPPING := map[ImageType]vk.ImageType {
		.ONE_DIMENSTIONAL   = vk.ImageType.D1,
		.TWO_DIMENSTIONAL   = vk.ImageType.D2,
		.THREE_DIMENSTIONAL = vk.ImageType.D3,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_FORMAT_MAPPING := map[ImageFormat]vk.Format {
		.DEPTH_32_SFLOAT = vk.Format.D32_SFLOAT,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_image :: proc(
		p_image: ^ImageResource,
		p_name: common.Name,
		p_image_desc: ImageDesc,
	) -> bool {

		vk_image_type, type_found := G_IMAGE_TYPE_MAPPING[p_image_desc.type]
		if type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_name(p_name),
				p_image_desc.type,
			)
			return false
		}

		vk_image_format, format_found := G_IMAGE_FORMAT_MAPPING[p_image_desc.format]
		if format_found == false {
			log.warnf(
				"Failed to create image %s, unsupported format: %s\n",
				common.get_name(p_name),
				p_image_desc.type,
			)
			return false
		}

		return true
	}

	//---------------------------------------------------------------------------//
}
