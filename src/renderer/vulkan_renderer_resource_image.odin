package renderer

import "core:mem"

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"
	import vma "../third_party/vma"
	import "../common"

	//---------------------------------------------------------------------------//

	@(private)
	BackendImageResource :: struct {
		vk_image:         vk.Image,
		all_mips_vk_view: vk.ImageView,
		per_mip_vk_view:  []vk.ImageView,
		allocation:       vma.Allocation,
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
	G_IMAGE_VIEW_TYPE_MAPPING := map[ImageType]vk.ImageViewType {
		.OneDimensional   = vk.ImageViewType.D1,
		.TwoDimensional   = vk.ImageViewType.D2,
		.ThreeDimensional = vk.ImageViewType.D3,
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
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		staging_buffer:        BufferRef,
		stating_buffer_offset: u32,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_images :: proc() {
		INTERNAL.staging_buffer = create_buffer(
			common.create_name("ImageStagingBuffer"),
			{size = common.MEGABYTE * 128, flags = {.HostWrite, .Mapped}, usage = {.TransferSrc}},
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_texture_image :: proc(
		p_name: common.Name,
		p_image_desc: ImageDesc,
		p_image_ref: ImageRef,
		p_image: ^ImageResource,
	) -> bool {

		assert(
			p_image_desc.format < .DepthFormatsStart && p_image_desc.format > .DepthFormatsEnd,
		)

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

		// Map vk image view type
		vk_image_view_type, view_type_found := G_IMAGE_VIEW_TYPE_MAPPING[p_image_desc.type]
		if view_type_found == false {
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
		image_aspect := ImageAspectFlags{.Color}
		usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_DST}

		if .Storage in p_image_desc.flags {
			usage += {.STORAGE}
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
			arrayLayers = 1,
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

		// Create image view containing all of the mips
		{
			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = p_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {
					aspectMask = vk_map_image_aspect(image_aspect),
					levelCount = u32(p_image_desc.mip_count),
					layerCount = 1,
				},
			}

			if vk.CreateImageView(
				   G_RENDERER.device,
				   &view_create_info,
				   nil,
				   &p_image.all_mips_vk_view,
			   ) != .SUCCESS {
				vma.destroy_image(G_RENDERER.vma_allocator, p_image.vk_image, p_image.allocation)
				return false
			}
		}

		// Now create image views per mip
		{
			p_image.per_mip_vk_view = make(
				[]vk.ImageView,
				u32(p_image_desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			num_image_views_created := 0

			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = p_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}

			for i in 0 .. p_image_desc.mip_count {
				view_create_info.subresourceRange.baseMipLevel = u32(i)
				if vk.CreateImageView(
					   G_RENDERER.device,
					   &view_create_info,
					   nil,
					   &p_image.per_mip_vk_view[i],
				   ) != .SUCCESS {
					break
				}
				num_image_views_created += 1
			}

			// Free the created image views if we failed to create any of the mip views
			if num_image_views_created < int(p_image_desc.mip_count) {
				vk.DestroyImageView(G_RENDERER.device, p_image.all_mips_vk_view, nil)
				for i in 0 .. num_image_views_created {
					vk.DestroyImageView(G_RENDERER.device, p_image.per_mip_vk_view[i], nil)
				}
				// Delete the image itself
				vma.destroy_image(G_RENDERER.vma_allocator, p_image.vk_image, p_image.allocation)
				return false
			}
		}

		texture_copy := TextureCopy {
			buffer             = INTERNAL.staging_buffer,
			image              = p_image_ref,
			mip_buffer_offsets = make(
				[]u32,
				int(p_image_desc.mip_count),
				G_RENDERER_ALLOCATORS.frame_allocator,
			),
		}

		texture_copy.image = p_image_ref
		texture_copy.buffer = INTERNAL.staging_buffer

		staging_buffer := get_buffer(INTERNAL.staging_buffer)

		// Queue image copies
		for mip_data, i in p_image_desc.data_per_mip {

			// Make sure we have enough space in the staging buffer
			assert(INTERNAL.stating_buffer_offset + u32(len(mip_data)) < staging_buffer.desc.size)

			mem.copy(
				mem.ptr_offset(staging_buffer.mapped_ptr, INTERNAL.stating_buffer_offset),
				raw_data(mip_data),
				len(mip_data),
			)

			texture_copy.mip_buffer_offsets[i] = INTERNAL.stating_buffer_offset

			INTERNAL.stating_buffer_offset += u32(len(mip_data))
		}

		append(&G_RENDERER.queued_textures_copies, texture_copy)
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_swap_images :: proc() {
		G_RENDERER.swap_image_refs = make(
			[]ImageRef,
			u32(len(G_RENDERER.swapchain_images)),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for vk_swap_image, i in G_RENDERER.swapchain_images {
			ref := allocate_image_ref(common.create_name("SwapImage"))

			swap_image := get_image(ref)

			swap_image.desc.type = .TwoDimensional
			swap_image.desc.format = G_IMAGE_FORMAT_MAPPING_VK[G_RENDERER.swapchain_format.format]
			swap_image.desc.mip_count = 1
			swap_image.desc.dimensions = {
				G_RENDERER.swap_extent.width,
				G_RENDERER.swap_extent.height,
				1,
			}
			swap_image.desc.flags = {.SwapImage}

			swap_image.vk_image = vk_swap_image
			swap_image.all_mips_vk_view = G_RENDERER.swapchain_image_views[i]

			G_RENDERER.swap_image_refs[i] = ref
		}
	}


	@(private)
	backend_create_depth_buffer :: proc(
		p_name: common.Name,
		p_depth_buffer_desc: ImageDesc,
		p_image_ref: ImageRef,
		p_depth_image: ^ImageResource,
	) -> bool {

		assert(
			p_depth_buffer_desc.format >
			.DepthFormatsStart &&
			p_depth_buffer_desc.format <
			.DepthFormatsEnd,
		)

		depth_image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {
				p_depth_buffer_desc.dimensions.x,
				p_depth_buffer_desc.dimensions.y,
				p_depth_buffer_desc.dimensions.z,
			},
			mipLevels = 1,
			arrayLayers = 1,
			format = G_IMAGE_FORMAT_MAPPING[p_depth_buffer_desc.format],
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			sharingMode = .EXCLUSIVE,
			samples = {._1},
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		if vma.create_image(
			   G_RENDERER.vma_allocator,
			   &depth_image_create_info,
			   &alloc_create_info,
			   &p_depth_image.vk_image,
			   &p_depth_image.allocation,
			   nil,
		   ) != .SUCCESS {
			log.warn("Failed to create depth buffer")
			return false
		}

		view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = p_depth_image.vk_image,
			viewType = .D2,
			format = G_IMAGE_FORMAT_MAPPING[p_depth_buffer_desc.format],
			subresourceRange = {
				aspectMask = {.DEPTH}, 
				levelCount = 1, 
				layerCount = 1,
			},
		}

		if vk.CreateImageView(G_RENDERER.device, &view_create_info, nil, &p_depth_image.all_mips_vk_view) != .SUCCESS {
			log.warn("Failed to create image view")
			return false
		}

		return true
	}

}

//---------------------------------------------------------------------------//
