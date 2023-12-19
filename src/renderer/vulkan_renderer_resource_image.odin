package renderer

//---------------------------------------------------------------------------//

import "../common"
import vma "../third_party/vma"
import "core:log"
import "core:math/linalg/glsl"
import "core:strings"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	BackendImageResource :: struct {
		vk_image:          vk.Image,
		vk_layout_per_mip: []vk.ImageLayout,
		all_mips_vk_view:  vk.ImageView,
		per_mip_vk_view:   []vk.ImageView,
		allocation:        vma.Allocation,
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
	RunningImageUpload :: struct {
		image_ref:             ImageRef,
		upload_finished_fence: vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	FinishedImageUpload :: struct {
		image_ref: ImageRef,
		fence:     vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		bindless_descriptor_pool: vk.DescriptorPool,
		bindless_array_updates:   [dynamic]ImageRef,
		finished_image_uploads:   [dynamic]FinishedImageUpload,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_images :: proc() {
		INTERNAL.bindless_array_updates = make([dynamic]ImageRef)
		INTERNAL.finished_image_uploads = make([dynamic]FinishedImageUpload, get_frame_allocator())
	}

	@(private)
	backend_create_texture_image :: proc(p_image_ref: ImageRef) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_idx := get_image_idx(p_image_ref)

		image := &g_resources.images[image_idx]
		backend_image := &g_resources.backend_images[image_idx]

		// Map vk image type
		vk_image_type, type_found := G_IMAGE_TYPE_MAPPING[image.desc.type]
		if type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Map vk image view type
		vk_image_view_type, view_type_found := G_IMAGE_VIEW_TYPE_MAPPING[image.desc.type]
		if view_type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Map vk image format
		vk_image_format, format_found := G_IMAGE_FORMAT_MAPPING[image.desc.format]
		if format_found == false {
			log.warnf(
				"Failed to create image %s, unsupported format: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Determine usage and aspect
		image_aspect := ImageAspectFlags{.Color}
		usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_DST}

		if .Storage in image.desc.flags {
			usage += {.STORAGE}
		}

		// Determine sample count
		vk_sample_count_flags := vk.SampleCountFlags{}
		for sample_count in ImageSampleFlagBits {
			if sample_count in image.desc.sample_count_flags {
				vk_sample_count_flags += {G_SAMPLE_COUNT_MAPPING[sample_count]}
			}
		}

		// Create image
		image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			mipLevels = u32(image.desc.mip_count),
			arrayLayers = 1,
			extent = {
				width = image.desc.dimensions.x,
				height = image.desc.dimensions.y,
				depth = image.desc.dimensions.z,
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
			&backend_image.vk_image,
			&backend_image.allocation,
			nil,
		); res != .SUCCESS {
			log.warnf("Failed to create image %s", res)
			return false
		}


		vk_name := strings.clone_to_cstring(
			common.get_string(image.desc.name),
			temp_arena.allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(backend_image.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		// Create image view containing all of the mips
		{
			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = backend_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {
					aspectMask = vk_map_image_aspect(image_aspect),
					levelCount = u32(image.desc.mip_count),
					layerCount = 1,
				},
			}

			if vk.CreateImageView(
				   G_RENDERER.device,
				   &view_create_info,
				   nil,
				   &backend_image.all_mips_vk_view,
			   ) !=
			   .SUCCESS {
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					backend_image.vk_image,
					backend_image.allocation,
				)
				return false
			}


			vk_name := strings.clone_to_cstring(
				common.get_string(image.desc.name),
				temp_arena.allocator,
			)

			name_info := vk.DebugUtilsObjectNameInfoEXT {
				sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
				objectHandle = u64(backend_image.all_mips_vk_view),
				objectType   = .IMAGE_VIEW,
				pObjectName  = vk_name,
			}

			vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		}

		// Now create image views per mip
		{
			backend_image.per_mip_vk_view = make(
				[]vk.ImageView,
				u32(image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_image.vk_layout_per_mip = make(
				[]vk.ImageLayout,
				u32(image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			num_image_views_created := 0

			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = backend_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}

			for i in 0 ..< image.desc.mip_count {
				backend_image.vk_layout_per_mip[i] = .UNDEFINED
				view_create_info.subresourceRange.baseMipLevel = u32(i)
				if vk.CreateImageView(
					   G_RENDERER.device,
					   &view_create_info,
					   nil,
					   &backend_image.per_mip_vk_view[i],
				   ) !=
				   .SUCCESS {
					break
				}

				vk_name := strings.clone_to_cstring(
					common.get_string(image.desc.name),
					temp_arena.allocator,
				)

				name_info := vk.DebugUtilsObjectNameInfoEXT {
					sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
					objectHandle = u64(backend_image.per_mip_vk_view[i]),
					objectType   = .IMAGE_VIEW,
					pObjectName  = vk_name,
				}

				vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

				num_image_views_created += 1
			}

			// Free the created image views if we failed to create any of the mip views
			if num_image_views_created < int(image.desc.mip_count) {
				vk.DestroyImageView(G_RENDERER.device, backend_image.all_mips_vk_view, nil)
				for i in 0 ..= num_image_views_created {
					vk.DestroyImageView(G_RENDERER.device, backend_image.per_mip_vk_view[i], nil)
				}
				// Delete the image itself
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					backend_image.vk_image,
					backend_image.allocation,
				)
				return false
			}
		}

		append(&INTERNAL.bindless_array_updates, p_image_ref)

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_swap_images :: proc() {

		// If those images are already created, this means that the swapchain is getting recreated
		is_recreating_swapchain := len(G_RENDERER.swap_image_refs) > 0

		if is_recreating_swapchain == false {
			G_RENDERER.swap_image_refs = make(
				[]ImageRef,
				u32(len(G_RENDERER.swapchain_images)),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			for _, i in G_RENDERER.swap_image_refs {
				G_RENDERER.swap_image_refs[i] = allocate_image_ref(common.create_name("SwapImage"))
			}
		}


		for vk_swap_image, i in G_RENDERER.swapchain_images {
			ref := G_RENDERER.swap_image_refs[i]
			image_idx := get_image_idx(ref)

			swap_image := &g_resources.images[image_idx]
			backend_swap_image := &g_resources.backend_images[image_idx]

			swap_image.desc.type = .TwoDimensional
			swap_image.desc.format = G_IMAGE_FORMAT_MAPPING_VK[G_RENDERER.swapchain_format.format]
			swap_image.desc.mip_count = 1
			swap_image.desc.dimensions = {
				G_RENDERER.swap_extent.width,
				G_RENDERER.swap_extent.height,
				1,
			}
			swap_image.desc.flags = {.SwapImage}

			backend_swap_image.vk_image = vk_swap_image
			backend_swap_image.all_mips_vk_view = G_RENDERER.swapchain_image_views[i]

			backend_swap_image.per_mip_vk_view = make(
				[]vk.ImageView,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.per_mip_vk_view[0] = G_RENDERER.swapchain_image_views[i]
			backend_swap_image.vk_layout_per_mip = make(
				[]vk.ImageLayout,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.vk_layout_per_mip[0] = .UNDEFINED

			G_RENDERER.swap_image_refs[i] = ref
		}
	}


	@(private)
	backend_create_image :: proc(p_image_ref: ImageRef) -> (res: bool) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_idx := get_image_idx(p_image_ref)
		image := &g_resources.images[image_idx]
		image_backend := &g_resources.backend_images[image_idx]

		image_type := vk.ImageType.D1
		#partial switch image.desc.type {
		case .TwoDimensional:
			image_type = .D2
		case .ThreeDimensional:
			image_type = .D3
		}

		usage := vk.ImageUsageFlags{}
		aspect_mask := vk.ImageAspectFlags{}

		if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {
			usage += {.DEPTH_STENCIL_ATTACHMENT}
			aspect_mask += {.DEPTH}

			if image.desc.format > .DepthStencilFormatsStart &&
			   image.desc.format < .DepthStencilFormatsEnd {
				aspect_mask += {.STENCIL}
			}

		} else {
			aspect_mask += {.COLOR}
			usage += {.COLOR_ATTACHMENT}
		}

		if .Sampled in image.desc.flags {
			usage += {.SAMPLED}
		}
		if .Storage in image.desc.flags {
			usage += {.STORAGE}
		}

		image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = image_type,
			extent = {image.desc.dimensions.x, image.desc.dimensions.y, image.desc.dimensions.z},
			mipLevels = 1,
			arrayLayers = 1,
			format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = usage,
			sharingMode = .EXCLUSIVE,
			samples = {._1},
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		create_result := vma.create_image(
			G_RENDERER.vma_allocator,
			&image_create_info,
			&alloc_create_info,
			&image_backend.vk_image,
			&image_backend.allocation,
			nil,
		)
		if create_result != .SUCCESS {
			return false
		}
		defer if res == false {
			vma.destroy_image(
				G_RENDERER.vma_allocator,
				image_backend.vk_image,
				image_backend.allocation,
			)
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(image.desc.name),
			temp_arena.allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(image_backend.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		view_type := vk.ImageViewType{}
		#partial switch image_type {
		case .D1:
			view_type = .D1
		case .D2:
			view_type = .D2
		case .D3:
			view_type = .D3
		}

		view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image_backend.vk_image,
			viewType = view_type,
			format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
			subresourceRange = {aspectMask = aspect_mask, levelCount = 1, layerCount = 1},
		}

		if vk.CreateImageView(
			   G_RENDERER.device,
			   &view_create_info,
			   nil,
			   &image_backend.all_mips_vk_view,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create image view")
			return false
		}
		defer if res == false {
			vk.DestroyImageView(G_RENDERER.device, image_backend.all_mips_vk_view, nil)
		}

		name_info = vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(image_backend.all_mips_vk_view),
			objectType   = .IMAGE_VIEW,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		append(&INTERNAL.bindless_array_updates, p_image_ref)

		image_backend.per_mip_vk_view = make(
			[]vk.ImageView,
			1,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		image_backend.vk_layout_per_mip = make(
			[]vk.ImageLayout,
			1,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		image_backend.vk_layout_per_mip[0] = .UNDEFINED

		view_create_info = vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image_backend.vk_image,
			viewType = G_IMAGE_VIEW_TYPE_MAPPING[image.desc.type],
			format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
			subresourceRange = {aspectMask = aspect_mask, levelCount = 1, layerCount = 1},
		}

		if vk.CreateImageView(
			   G_RENDERER.device,
			   &view_create_info,
			   nil,
			   &image_backend.per_mip_vk_view[0],
		   ) !=
		   .SUCCESS {
			return false
		}

		name_info = vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(image_backend.per_mip_vk_view[0]),
			objectType   = .IMAGE_VIEW,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		return true
	}

	//---------------------------------------------------------------------------//

	backend_destroy_image :: proc(p_image_ref: ImageRef) {
		img_idx := get_image_idx(p_image_ref)
		image := &g_resources.images[img_idx]
		backend_image := &g_resources.backend_images[img_idx]
		if (.SwapImage in image.desc.flags) == false {
			// For swap chain, these are destroyed in recreate_swapchain
			vma.destroy_image(G_RENDERER.vma_allocator, backend_image.vk_image, nil)
			vk.DestroyImageView(G_RENDERER.device, backend_image.all_mips_vk_view, nil)
			for image_view in backend_image.per_mip_vk_view {
				vk.DestroyImageView(G_RENDERER.device, image_view, nil)
			}
		}
		delete(backend_image.per_mip_vk_view, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(backend_image.vk_layout_per_mip, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_batch_update_bindless_array_entries :: proc() {
		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		num_writes := len(INTERNAL.bindless_array_updates)
		if num_writes == 0 {
			return
		}

		bindless_bind_group_idx := get_bind_group_idx(
			G_RENDERER.bindless_textures_array_bind_group_ref,
		)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make([]vk.WriteDescriptorSet, u32(num_writes), temp_arena.allocator)

		image_infos := make([]vk.DescriptorImageInfo, u32(num_writes), temp_arena.allocator)

		for image_ref, i in INTERNAL.bindless_array_updates {

			image_idx := get_image_idx(image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			// Update the descriptor in the bindless array
			image_infos[i] = vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView   = backend_image.all_mips_vk_view,
			}
			descriptor_writes[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				descriptorCount = 1,
				descriptorType  = .SAMPLED_IMAGE,
				dstSet          = bindless_bind_group.vk_descriptor_set,
				pImageInfo      = &image_infos[i],
				dstArrayElement = image.bindless_idx,
				dstBinding      = 6,
			}
		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(num_writes),
			raw_data(descriptor_writes),
			0,
			nil,
		)
		clear(&INTERNAL.bindless_array_updates)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_upload_initialize :: proc(p_ref: ImageRef) {

		image_idx := get_image_idx(p_ref)
		image := &g_resources.images[image_idx]
		backend_image := &g_resources.backend_images[image_idx]

		// If we have a dedicated transfer queue, then hand off ownership
		// to the transfer queue for the data uploads
		to_transfer_barrier := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			oldLayout = .UNDEFINED,
			newLayout = .TRANSFER_DST_OPTIMAL,
			image = backend_image.vk_image,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseArrayLayer = 0,
				layerCount = 1,
				baseMipLevel = 0,
				levelCount = u32(image.desc.mip_count),
			},
			dstAccessMask = {.TRANSFER_WRITE},
		}

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			transfer_cmd_buff := get_frame_transfer_cmd_buffer_post_graphics()

			vk.CmdPipelineBarrier(
				transfer_cmd_buff,
				{.TOP_OF_PIPE},
				{.TRANSFER},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&to_transfer_barrier,
			)

			return
		}

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]

		// Otherwise just prepare it to copy
		vk.CmdPipelineBarrier(
			cmd_buffer.vk_cmd_buff,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			0,
			nil,
			1,
			&to_transfer_barrier,
		)

	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_issue_image_copy :: proc(
		p_image_ref: ImageRef,
		p_current_mip: u8,
		p_staging_buffer_ref: BufferRef,
		p_staging_buffer_offset: u32,
		p_size: glsl.uvec2,
		p_offset: glsl.uvec2,
	) {

		image_idx := get_image_idx(p_image_ref)
		backend_image := &g_resources.backend_images[image_idx]

		backend_buffer := &g_resources.backend_buffers[get_buffer_idx(p_staging_buffer_ref)]

		image_copy := vk.BufferImageCopy {
			bufferOffset = vk.DeviceSize(p_staging_buffer_offset),
			imageOffset = vk.Offset3D{i32(p_offset.x), i32(p_offset.y), 0},
			imageSubresource = {
				aspectMask = {.COLOR},
				baseArrayLayer = 0,
				layerCount = 1,
				mipLevel = u32(p_current_mip),
			},
			imageExtent = {width = p_size.x, height = p_size.y, depth = 1},
		}

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]
		vk_cmd_buff := cmd_buffer.vk_cmd_buff

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			vk_cmd_buff = get_frame_transfer_cmd_buffer_post_graphics()
		}

		vk.CmdCopyBufferToImage(
			vk_cmd_buff,
			backend_buffer.vk_buffer,
			backend_image.vk_image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&image_copy,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_finish_image_copy :: proc(p_image_ref: ImageRef) {
		append(
			&INTERNAL.finished_image_uploads,
			FinishedImageUpload{
				image_ref = p_image_ref,
				fence = G_RENDERER.transfer_fences_post_graphics[get_frame_idx()],
			},
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_finalize_async_image_copies :: proc() {

		finished_image_uploads := make([dynamic]FinishedImageUpload, get_next_frame_allocator())

		for finished_upload in &INTERNAL.finished_image_uploads {

			if vk.GetFenceStatus(G_RENDERER.device, finished_upload.fence) != .SUCCESS {
				append(&finished_image_uploads, finished_upload)
				continue
			}

			image_idx := get_image_idx(finished_upload.image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			image.flags += {.IsUploaded}

			if image.desc.file_mapping.mapped_ptr == nil {
				for mip_data in image.desc.data_per_mip {
					delete(mip_data, image.desc.mip_data_allocator)
				}
			} else {
				common.unmap_file(image.desc.file_mapping)
				image.desc.file_mapping = {}	
			}

			cmd_buffer_ref := get_frame_cmd_buffer_ref()
			cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]

			to_sample_barrier := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcAccessMask = {.TRANSFER_WRITE},
				image = backend_image.vk_image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseArrayLayer = 0,
					layerCount = 1,
					baseMipLevel = 0,
					levelCount = u32(image.desc.mip_count),
				},
			}

			if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				transfer_cmd_buff := get_frame_transfer_cmd_buffer_pre_graphics()
				to_sample_barrier.srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index
				to_sample_barrier.dstQueueFamilyIndex = G_RENDERER.queue_family_graphics_index

				// Release
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.TRANSFER},
					{.TOP_OF_PIPE},
					nil,
					0,
					nil,
					0,
					nil,
					1,
					&to_sample_barrier,
				)

				// Acquire
				vk.CmdPipelineBarrier(
					cmd_buffer.vk_cmd_buff,
					{.TRANSFER},
					{.TOP_OF_PIPE},
					nil,
					0,
					nil,
					0,
					nil,
					1,
					&to_sample_barrier,
				)

				continue
			}

			to_sample_barrier.dstAccessMask = {.SHADER_READ}

			vk.CmdPipelineBarrier(
				cmd_buffer.vk_cmd_buff,
				{.TRANSFER},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&to_sample_barrier,
			)
		}

		INTERNAL.finished_image_uploads = finished_image_uploads
	}
}
