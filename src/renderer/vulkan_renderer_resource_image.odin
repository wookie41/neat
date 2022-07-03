package renderer

import "core:mem"

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"
	import vma "../third_party/vma"
	import "../common"

	//---------------------------------------------------------------------------//

	//---------------------------------------------------------------------------//

	BackendImageResource :: struct {
		vk_image:   vk.Image,
		allocation: vma.Allocation,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_TYPE_MAPPING := map[ImageType]vk.ImageType {
		.OneDimensional   = vk.ImageType.D1,
		.TwoDimensional   = vk.ImageType.D2,
		.ThreeDimensional = vk.ImageType.D3,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_FORMAT_MAPPING := map[ImageFormat]vk.Format {
		.Depth32SFloat = vk.Format.D32_SFLOAT,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_SAMPLE_COUNT_MAPPING := map[ImageSampleFlagBits]vk.SampleCountFlag {
		._1  = ._1,
		._2  = ._2,
		._4  = ._4,
		._8  = ._8,
		._16 = ._16,
		._32 = ._32,
		._64 = ._64,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_ASPECT_MAPPING := map[ImageAspectFlagBits]vk.ImageAspectFlag {
		.Color  = .COLOR,
		.Depth  = .DEPTH,
		.Stencil  = .STENCIL,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		staging_buffer:        BufferRef,
		stating_buffer_offset: u32,
		queued_image_copies:   [dynamic]BufferImageCopy,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_images :: proc() {
		INTERNAL.staging_buffer = create_buffer(
			common.create_name("ImageStagingBuffer"),
			{size = common.MEGABYTE * 128, flags = {.HostWrite, .Mapped}, usage = {.TransferSrc}},
		)
		INTERNAL.queued_image_copies = make(
			[dynamic]QueuedImageCopy,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_image :: proc(
		p_name: common.Name,
		p_image_desc: ImageDesc,
		p_image_ref: ImageRef,
		p_image: ^ImageResource,
	) -> bool {

		// Map vk image type
		vk_image_type, type_found := G_IMAGE_TYPE_MAPPING[p_image_desc.type]
		if type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_name(p_name),
				p_image_desc.type,
			)
			return false
		}

		// Map vk image format
		vk_image_format, format_found := G_IMAGE_FORMAT_MAPPING[p_image_desc.format]
		if format_found == false {
			log.warnf(
				"Failed to create image %s, unsupported format: %s\n",
				common.get_name(p_name),
				p_image_desc.type,
			)
			return false
		}

		// Determine usage and aspect
		image_aspect : vk.ImageAspectFlags
		usage: vk.ImageUsageFlags = {.SAMPLED, .TRANSFER_SRC, .TRANSFER_DST}

		if .Storage in p_image_desc.flags {
			usage += {.STORAGE}
		}

		if p_image_desc.format > .DepthFormatsStart && p_image_desc.format < .DepthFormatsEnd {
			usage += {.DEPTH_STENCIL_ATTACHMENT}
			image_aspect = {.Depth, .Stencil}
			
		} else {
			usage += {.COLOR_ATTACHMENT}
			image_aspect = {.Color}
		}

		// Determine sample count
		vk_sample_count_flags := vk.SampleCountFlags{}
		for sample_count in ImageSampleFlagBits {
			if sample_count in p_image_desc.sample_count_flags {
				vk_sample_count_flags += {G_SAMPLE_COUNT_MAPPING[sample_count]}
			}
		}

		// Create image
		image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			mipLevels = u32(p_image_desc.mip_count),
			arrayLayers = u32(p_image_desc.layer_count),
			extent = {
				width = p_image_desc.dimensions.x,
				height = p_image_desc.dimensions.y,
				depth = p_image_desc.dimensions.z,
			},
			imageType = vk_image_type,
			format = vk_image_format,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = usage,
			sharingMode = .EXCLUSIVE,
			samples = vk_sample_count_flags,
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		if res := vma.create_image(
			   G_RENDERER.vma_allocator,
			   &image_create_info,
			   &alloc_create_info,
			   &p_image.vk_image,
			   &p_image.allocation,
			   nil,
		   ); res != .SUCCESS {
			log.warnf("Failed to create image %s", res)
			return false
		}


		staging_buffer := get_buffer(INTERNAL.staging_buffer)
		// Queue image copies if the user provided data
		for layer_data, layer in p_image_desc.data {
			for mip_data, mip in layer_data {

				// Make sure we have enough space in the staging buffer
				assert(INTERNAL.stating_buffer_offset + u32(len(mip_data)) < staging_buffer.desc.size)

				mem.copy(
					mem.ptr_offset(staging_buffer.mapped_ptr, INTERNAL.stating_buffer_offset),
					raw_data(mip_data),
					len(mip_data),
				)

				copy := BufferImageCopy {
					image  = p_image_ref,
					buffer = INTERNAL.staging_buffer,
					buffer_offset = INTERNAL.stating_buffer_offset,
					subresource_range = {
						aspect = image_aspect,
						base_layer = u8(layer),
						layer_count = 1,
						base_mip = u8(mip),
						mip_count = 1,
					},
				}

				append(&INTERNAL.queued_image_copies, copy)

				INTERNAL.stating_buffer_offset += u32(len(mip_data))
			}
		}
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	execute_queued_image_copies :: proc() {

		cmd_buff := get_frame_cmd_buffer_handle()

		for queued_copy in INTERNAL.queued_image_copies {
			cmd_copy_buffer_to_image(cmd_buff, queued_copy)
		}

		clear(&INTERNAL.queued_image_copies)
	}

	//---------------------------------------------------------------------------//

	@(private)
	vk_map_image_aspect :: #force_inline proc(p_aspect: ImageAspectFlags) -> vk.ImageAspectFlags {
		vk_image_aspect : vk.ImageAspectFlags
        for aspect in ImageAspectFlagBits {
            if p_aspect in p_copy.subresource_range.aspect {
                vk_image_aspect += {G_IMAGE_ASPECT_MAPPING[p_aspect]}
            }
        }
		return vk_image_aspect
	}

	//---------------------------------------------------------------------------//
}
