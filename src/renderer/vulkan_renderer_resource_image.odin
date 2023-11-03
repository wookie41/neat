package renderer

//---------------------------------------------------------------------------//

import "../common"
import vma "../third_party/vma"
import "core:log"
import "core:mem"
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
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		staging_buffer:           BufferRef,
		staging_buffer_offset:    u32,
		bindless_descriptor_pool: vk.DescriptorPool,
		bindless_array_updates:   [dynamic]ImageRef,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_images :: proc() {
		INTERNAL.staging_buffer = allocate_buffer_ref(common.create_name("ImageStagingBuffer"))
		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer)]
		staging_buffer.desc.size = common.MEGABYTE * 128
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}
		create_buffer(INTERNAL.staging_buffer)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_texture_image :: proc(p_image_ref: ImageRef) -> bool {

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
			G_RENDERER_ALLOCATORS.names_allocator,
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
				G_RENDERER_ALLOCATORS.names_allocator,
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
					G_RENDERER_ALLOCATORS.names_allocator,
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

		texture_copy := TextureCopy {
			buffer_ref         = INTERNAL.staging_buffer,
			image_ref          = p_image_ref,
			mip_buffer_offsets = make(
				[]u32,
				int(image.desc.mip_count),
				G_RENDERER_ALLOCATORS.frame_allocator,
			),
		}

		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer)]

		// Queue image copies
		for mip_data, i in image.desc.data_per_mip {

			// Make sure we have enough space in the staging buffer
			assert(INTERNAL.staging_buffer_offset + u32(len(mip_data)) < staging_buffer.desc.size)

			// Copy mip data into the staging buffer
			mem.copy(
				mem.ptr_offset(staging_buffer.mapped_ptr, INTERNAL.staging_buffer_offset),
				raw_data(mip_data),
				len(mip_data),
			)

			texture_copy.mip_buffer_offsets[i] = INTERNAL.staging_buffer_offset

			INTERNAL.staging_buffer_offset += u32(len(mip_data))
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

			G_RENDERER.swap_image_refs[i] = ref
		}
	}


	@(private)
	backend_create_depth_buffer :: proc(
		p_name: common.Name,
		p_depth_buffer_desc: ImageDesc,
		p_image_ref: ImageRef,
	) -> bool {

		image_idx := get_image_idx(p_image_ref)
		depth_image_backend := &g_resources.backend_images[image_idx]

		assert(
			p_depth_buffer_desc.format > .DepthFormatsStart &&
			p_depth_buffer_desc.format < .DepthFormatsEnd,
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
			   &depth_image_backend.vk_image,
			   &depth_image_backend.allocation,
			   nil,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create depth buffer")
			return false
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(p_name),
			G_RENDERER_ALLOCATORS.names_allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(depth_image_backend.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)


		view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = depth_image_backend.vk_image,
			viewType = .D2,
			format = G_IMAGE_FORMAT_MAPPING[p_depth_buffer_desc.format],
			subresourceRange = {aspectMask = {.DEPTH}, levelCount = 1, layerCount = 1},
		}

		if vk.CreateImageView(
			   G_RENDERER.device,
			   &view_create_info,
			   nil,
			   &depth_image_backend.all_mips_vk_view,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create image view")
			return false
		}

		name_info = vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(depth_image_backend.all_mips_vk_view),
			objectType   = .IMAGE_VIEW,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		return true
	}

	//---------------------------------------------------------------------------//

	backend_destroy_image :: proc(p_image_ref: ImageRef) {
		backend_image := &g_resources.backend_images[get_image_idx(p_image_ref)]
		vk.DestroyImageView(G_RENDERER.device, backend_image.all_mips_vk_view, nil)
		for image_view in backend_image.per_mip_vk_view {
			vk.DestroyImageView(G_RENDERER.device, image_view, nil)
		}
		vma.destroy_image(G_RENDERER.vma_allocator, backend_image.vk_image, nil)
		delete(backend_image.per_mip_vk_view, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(backend_image.vk_layout_per_mip, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_execute_queued_texture_copies :: proc(p_cmd_buff_ref: CommandBufferRef) {

		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]

		VkCopyEntry :: struct {
			buffer:     vk.Buffer,
			image:      vk.Image,
			mip_copies: []vk.BufferImageCopy,
		}

		to_transfer_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(to_transfer_barriers, G_RENDERER_ALLOCATORS.temp_allocator)

		vk_copies := make(
			[]VkCopyEntry,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(vk_copies, G_RENDERER_ALLOCATORS.temp_allocator)

		to_sample_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(to_sample_barriers, G_RENDERER_ALLOCATORS.temp_allocator)

		for _, i in G_RENDERER.queued_textures_copies {

			texture_copy := G_RENDERER.queued_textures_copies[i]

			image_idx := get_image_idx(texture_copy.image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			buffer_idx := get_buffer_idx(texture_copy.buffer_ref)
			buffer := &g_resources.buffers[buffer_idx]
			backend_buffer := &g_resources.backend_buffers[buffer_idx]

			// Crate a transfer barrier for the entire texture, including all of it's mips
			{
				image_barrier := &to_transfer_barriers[i]
				image_barrier.sType = .IMAGE_MEMORY_BARRIER
				image_barrier.oldLayout = .UNDEFINED
				image_barrier.newLayout = .TRANSFER_DST_OPTIMAL
				image_barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.image = backend_image.vk_image
				image_barrier.subresourceRange.aspectMask = {.COLOR}
				image_barrier.subresourceRange.baseArrayLayer = 0
				image_barrier.subresourceRange.layerCount = 1
				image_barrier.subresourceRange.baseMipLevel = 0
				image_barrier.subresourceRange.levelCount = u32(image.desc.mip_count)
				image_barrier.dstAccessMask = {.TRANSFER_WRITE}
			}

			// Create a to-sample barrier for the entire texture, including all of it's mips
			{
				image_barrier := &to_sample_barriers[i]
				image_barrier^ = to_transfer_barriers[i]

				image_barrier.oldLayout = .TRANSFER_DST_OPTIMAL
				image_barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
				image_barrier.srcAccessMask = {.TRANSFER_WRITE}
				image_barrier.dstAccessMask = {.SHADER_READ}
			}

			vk_copy_entry := VkCopyEntry {
				buffer     = backend_buffer.vk_buffer,
				image      = backend_image.vk_image,
				mip_copies = make(
					[]vk.BufferImageCopy,
					u32(len(texture_copy.mip_buffer_offsets)),
					G_RENDERER_ALLOCATORS.temp_allocator,
				),
			}

			// Create the vulkan copies
			for offset, mip in texture_copy.mip_buffer_offsets {

				vk_copy_entry.mip_copies[mip] = {
					bufferOffset = vk.DeviceSize(offset),
					imageSubresource = {
						aspectMask = {.COLOR},
						baseArrayLayer = 0,
						layerCount = 1,
						mipLevel = u32(mip),
					},
					imageExtent = {
						width = image.desc.dimensions[0] >> u32(mip),
						height = image.desc.dimensions[1] >> u32(mip),
						depth = 1,
					},
				}


				backend_image.vk_layout_per_mip[mip] = .SHADER_READ_ONLY_OPTIMAL
			}

			vk_copies[i] = vk_copy_entry

			append(&INTERNAL.bindless_array_updates, texture_copy.image_ref)
		}
		defer {
			for vk_copy in vk_copies {
				defer delete(vk_copy.mip_copies, G_RENDERER_ALLOCATORS.temp_allocator)

			}
		}

		// Transition the images to transfer
		vk.CmdPipelineBarrier(
			backend_cmd_buffer.vk_cmd_buff,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			0,
			nil,
			u32(len(vk_copies)),
			&to_transfer_barriers[0],
		)

		// Copy the data image
		for copy, i in vk_copies {

			vk.CmdCopyBufferToImage(
				backend_cmd_buffer.vk_cmd_buff,
				copy.buffer,
				copy.image,
				.TRANSFER_DST_OPTIMAL,
				u32(len(copy.mip_copies)),
				raw_data(copy.mip_copies),
			)

			// Transition the image to sample
			vk.CmdPipelineBarrier(
				backend_cmd_buffer.vk_cmd_buff,
				{.TRANSFER},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&to_sample_barriers[i],
			)
		}
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_batch_update_bindless_array_entries :: proc() {

		num_writes := len(INTERNAL.bindless_array_updates)
		if num_writes == 0 {
			return
		}

		bindless_bind_group_idx := get_bind_group_idx(G_RENDERER.bindless_textures_array_bind_group_ref)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make(
			[]vk.WriteDescriptorSet,
			u32(num_writes),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_writes, G_RENDERER_ALLOCATORS.temp_allocator)

		image_infos := make(
			[]vk.DescriptorImageInfo,
			u32(num_writes),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(image_infos, G_RENDERER_ALLOCATORS.temp_allocator)

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

}
