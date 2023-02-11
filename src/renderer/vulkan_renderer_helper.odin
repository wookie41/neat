package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private)
	G_IMAGE_FORMAT_MAPPING := map[ImageFormat]vk.Format {
		.Depth32SFloat = .D32_SFLOAT,
		.R32UInt       = .R32_UINT,
		.R32Int        = .R32_SINT,
		.R32SFloat     = .R32_SFLOAT,
		.RG32UInt      = .R32G32_UINT,
		.RG32Int       = .R32G32_SINT,
		.RG32SFloat    = .R32G32_SFLOAT,
		.RGB32UInt     = .R32G32B32_UINT,
		.RGB32Int      = .R32G32B32_SINT,
		.RGB32SFloat   = .R32G32B32A32_SFLOAT,
		.RGBA32UInt    = .R32G32B32A32_UINT,
		.RGBA32Int     = .R32G32B32A32_SINT,
		.RGBA32SFloat  = .R32G32B32A32_SFLOAT,
		.R11G11B10     = .B10G11R11_UFLOAT_PACK32,
		.RGBA8_SRGB    = .R8G8B8A8_SRGB,
		.BGRA8_SRGB    = .B8G8R8A8_SRGB,
	}

	@(private)
	G_IMAGE_FORMAT_MAPPING_VK := map[vk.Format]ImageFormat {
		.D32_SFLOAT              = .Depth32SFloat,
		.R32_UINT                = .R32UInt,
		.R32_SINT                = .R32Int,
		.R32_SFLOAT              = .R32SFloat,
		.R32G32_UINT             = .RG32UInt,
		.R32G32_SINT             = .RG32Int,
		.R32G32_SFLOAT           = .RG32SFloat,
		.R32G32B32_UINT          = .RGB32UInt,
		.R32G32B32_SINT          = .RGB32Int,
		.R32G32B32A32_SFLOAT     = .RGB32SFloat,
		.R32G32B32A32_UINT       = .RGBA32UInt,
		.R32G32B32A32_SINT       = .RGBA32Int,
		.R32G32B32A32_SFLOAT     = .RGBA32SFloat,
		.B10G11R11_UFLOAT_PACK32 = .R11G11B10,
		.R8G8B8A8_SRGB           = .RGBA8_SRGB,
		.B8G8R8A8_SRGB           = .BGRA8_SRGB,
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

	@(private)
	map_pipeline_bind_point :: proc(p_pipeline_type: PipelineType) -> vk.PipelineBindPoint {
		if p_pipeline_type == .Graphics {
			return .GRAPHICS
		} else if p_pipeline_type == .Compute {
			return .COMPUTE
		} else if p_pipeline_type == .Raytracing {
			assert(false)
		} else {
			assert(false)
		}
		return .GRAPHICS
	}

	//---------------------------------------------------------------------------//

}


