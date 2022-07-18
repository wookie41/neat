package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private)
	G_IMAGE_FORMAT_MAPPING := map[ImageFormat]vk.Format {
		.Depth32SFloat = .D32_SFLOAT,
		.B8G8R8A8_SRGB = .B8G8R8A8_SRGB,

	}

	@(private)
	G_IMAGE_FORMAT_MAPPING_VK := map[vk.Format]ImageFormat {
		.D32_SFLOAT = .Depth32SFloat,
		.B8G8R8A8_SRGB = .B8G8R8A8_SRGB,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_ASPECT_MAPPING := map[ImageAspectFlagBits]vk.ImageAspectFlag {
		.Color   = .COLOR,
		.Depth   = .DEPTH,
		.Stencil = .STENCIL,
	}

	//---------------------------------------------------------------------------//

	@(private)
	vk_map_image_aspect :: proc(p_aspect: ImageAspectFlags) -> vk.ImageAspectFlags {
		vk_image_aspect: vk.ImageAspectFlags
		for aspect_bit in ImageAspectFlagBits {
			if aspect_bit in p_aspect {
				vk_image_aspect += {G_IMAGE_ASPECT_MAPPING[aspect_bit]}
			}
		}
		return vk_image_aspect
	}

    //---------------------------------------------------------------------------//
}
