package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	G_IMAGE_FORMAT_MAPPING := map[ImageFormat]vk.Format {
		.Depth16         = .D16_UNORM,
		.Depth32SFloat   = .D32_SFLOAT,
		.R8UNorm         = .R8_UNORM,
		.R32UInt         = .R32_UINT,
		.R32Int          = .R32_SINT,
		.R32SFloat       = .R32_SFLOAT,
		.RG8UNorm        = .R8G8_UNORM,
		.RG32UInt        = .R32G32_UINT,
		.RG32Int         = .R32G32_SINT,
		.RG32SFloat      = .R32G32_SFLOAT,
		.RGB8UNorm       = .R8G8B8_UNORM,
		.RGB32UInt       = .R32G32B32_UINT,
		.RGB32Int        = .R32G32B32_SINT,
		.RGB16SFloat     = .R16G16B16_SFLOAT,
		.RGBA16SFloat    = .R16G16B16A16_SFLOAT,
		.RGB32SFloat     = .R32G32B32_SFLOAT,
		.RGBA8UNorm      = .R8G8B8A8_UNORM,
		.RGBA16SNorm     = .R16G16B16A16_SNORM,
		.RGBA32UInt      = .R32G32B32A32_UINT,
		.RGBA32Int       = .R32G32B32A32_SINT,
		.RGBA32SFloat    = .R32G32B32A32_SFLOAT,
		.R11G11B10UFloat = .B10G11R11_UFLOAT_PACK32,
		.RGBA8_SRGB      = .R8G8B8A8_SRGB,
		.BGRA8_SRGB      = .B8G8R8A8_SRGB,
		.BC1_RGB_UNorm   = .BC1_RGB_UNORM_BLOCK,
		.BC1_RGB_SRGB    = .BC1_RGB_SRGB_BLOCK,
		.BC1_RGBA_UNorm  = .BC1_RGBA_UNORM_BLOCK,
		.BC1_RGBA_SRGB   = .BC1_RGBA_SRGB_BLOCK,
		.BC2_UNorm       = .BC2_UNORM_BLOCK,
		.BC2_SRGB        = .BC2_SRGB_BLOCK,
		.BC3_UNorm       = .BC3_UNORM_BLOCK,
		.BC3_SRGB        = .BC3_SRGB_BLOCK,
		.BC4_UNorm       = .BC4_UNORM_BLOCK,
		.BC4_SNorm       = .BC4_SNORM_BLOCK,
		.BC5_UNorm       = .BC5_UNORM_BLOCK,
		.BC5_SNorm       = .BC5_SNORM_BLOCK,
		.BC6H_UFloat     = .BC6H_UFLOAT_BLOCK,
		.BC6H_SFloat     = .BC6H_SFLOAT_BLOCK,
		.BC7_UNorm       = .BC7_UNORM_BLOCK,
		.BC7_SRGB        = .BC7_SRGB_BLOCK,
	}

	@(private)
	G_IMAGE_FORMAT_MAPPING_VK := map[vk.Format]ImageFormat {
		.D16_UNORM               = .Depth16,
		.D32_SFLOAT              = .Depth32SFloat,
		.R32_UINT                = .R32UInt,
		.R32_SINT                = .R32Int,
		.R32_SFLOAT              = .R32SFloat,
		.R32G32_UINT             = .RG32UInt,
		.R32G32_SINT             = .RG32Int,
		.R32G32_SFLOAT           = .RG32SFloat,
		.R32G32B32_UINT          = .RGB32UInt,
		.R32G32B32_SINT          = .RGB32Int,
		.R16G16B16_SFLOAT        = .RGB16SFloat,
		.R32G32B32_SFLOAT        = .RGB32SFloat,
		.R32G32B32A32_UINT       = .RGBA32UInt,
		.R32G32B32A32_SINT       = .RGBA32Int,
		.R16G16B16A16_SFLOAT     = .RGBA16SFloat,
		.R32G32B32A32_SFLOAT     = .RGBA32SFloat,
		.B10G11R11_UFLOAT_PACK32 = .R11G11B10UFloat,
		.R8G8B8A8_SRGB           = .RGBA8_SRGB,
		.B8G8R8A8_SRGB           = .BGRA8_SRGB,
		.BC1_RGB_UNORM_BLOCK     = .BC1_RGB_UNorm,
		.BC1_RGB_SRGB_BLOCK      = .BC1_RGB_SRGB,
		.BC1_RGBA_UNORM_BLOCK    = .BC1_RGBA_UNorm,
		.BC1_RGBA_SRGB_BLOCK     = .BC1_RGBA_SRGB,
		.BC2_UNORM_BLOCK         = .BC2_UNorm,
		.BC2_SRGB_BLOCK          = .BC2_SRGB,
		.BC3_UNORM_BLOCK         = .BC3_UNorm,
		.BC3_SRGB_BLOCK          = .BC3_SRGB,
		.BC4_UNORM_BLOCK         = .BC4_UNorm,
		.BC4_SNORM_BLOCK         = .BC4_SNorm,
		.BC5_UNORM_BLOCK         = .BC5_UNorm,
		.BC5_SNORM_BLOCK         = .BC5_SNorm,
		.BC6H_UFLOAT_BLOCK       = .BC6H_UFloat,
		.BC6H_SFLOAT_BLOCK       = .BC6H_SFloat,
		.BC7_UNORM_BLOCK         = .BC7_UNorm,
		.BC7_SRGB_BLOCK          = .BC7_SRGB,
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
