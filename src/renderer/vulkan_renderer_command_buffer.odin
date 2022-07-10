package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"
	import "core:log"


	//---------------------------------------------------------------------------//

	CommandBufferEntry :: struct {
		desc:     CommandBufferDesc,
		cmd_buff: vk.CommandBuffer,
	}

	@(private = "file")
	INTERNAL: struct {
		command_buffers:  []CommandBufferEntry,
		command_pools:    []vk.CommandPool,
		cmd_buffer_count: u32,
	}


	//---------------------------------------------------------------------------//

	init_command_buffers :: proc(p_options: InitOptions) -> bool {

		// Create command pools
		{
			using G_RENDERER

			pool_info := vk.CommandPoolCreateInfo {
				sType = .COMMAND_POOL_CREATE_INFO,
				queueFamilyIndex = u32(queue_family_graphics_index),
				flags = {.RESET_COMMAND_BUFFER},
			}

			INTERNAL.command_pools = make(
				[]vk.CommandPool,
				int(num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			for i in 0 ..< num_frames_in_flight {
				if vk.CreateCommandPool(device, &pool_info, nil, &INTERNAL.command_pools[i]) != .SUCCESS {
					log.error("Couldn't create command pool")
					return false
				}
			}
		}


		return true
	}

	//---------------------------------------------------------------------------//

	allocate_command_buffer :: proc(p_cmd_buffer_desc: CommandBufferDesc) -> (
		CommandBufferHandle,
		bool,
	) {
		assert(INTERNAL.cmd_buffer_count < u32(len(INTERNAL.command_buffers)))

		idx := INTERNAL.cmd_buffer_count
		alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = INTERNAL.command_pools[p_cmd_buffer_desc.frame],
			level              = .PRIMARY if .Primary in p_cmd_buffer_desc.flags else .SECONDARY,
			commandBufferCount = 1,
		}

		if vk.AllocateCommandBuffers(
			   G_RENDERER.device,
			   &alloc_info,
			   &INTERNAL.command_buffers[idx].cmd_buff,
		   ) != .SUCCESS {
			log.error("Couldn't allocate command buffers")
			return CommandBufferHandle(0), false
		}

		INTERNAL.command_buffers[idx].desc = p_cmd_buffer_desc

		INTERNAL.cmd_buffer_count += 1
		return CommandBufferHandle(idx), true
	}

	//---------------------------------------------------------------------------//

	cmd_insert_image_barrier :: proc(
		p_cmd_buff: CommandBufferHandle,
		p_image_barrier: ImageBarrier,
	) {

	}

	//---------------------------------------------------------------------------//


	cmd_copy_buffer_to_image :: proc(
		p_cmd_buff: CommandBufferHandle,
		p_copies: [dynamic]BufferImageCopy,
	) {

		cmd_buff := INTERNAL.command_buffers[u32(p_cmd_buff)]

		num_placed_barries := 0
		image_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(p_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(image_barriers)

		// Used to track which images have barriers placed for them already
		image_with_barriers := make(
			map[ImageRef]bool,
			len(p_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(image_with_barriers)

		for copy in p_copies {

			image := get_image(copy.image)
			buffer := get_buffer(copy.buffer)

			// @TODO Create a cmd_place_image_barriers command in the command buffer 
			// so we can track the layout of the image in there

			// For now we just place a barriers for the entire image
			if (copy.image in image_with_barriers) == false {

				image_barrier := &image_barriers[num_placed_barries]
				image_barrier.sType = .IMAGE_MEMORY_BARRIER
				image_barrier.oldLayout = .UNDEFINED // #FIXME ASSUMPTION UNTIL WE HAVE IMAGE LAYOUT TRACKING
				image_barrier.newLayout = .TRANSFER_DST_OPTIMAL
				image_barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.image = image.vk_image
				image_barrier.subresourceRange.aspectMask = vk_map_image_aspect(
					copy.regions[0].subresource_range.aspect,
				)
				image_barrier.subresourceRange.baseArrayLayer = 0
				image_barrier.subresourceRange.layerCount = u32(image.desc.layer_count)
				image_barrier.subresourceRange.baseMipLevel = 0
				image_barrier.subresourceRange.levelCount = u32(image.desc.mip_count)
				image_barrier.dstAccessMask = {.TRANSFER_WRITE}


				num_placed_barries += 1
			}

			vk_copies := make(
				[]vk.BufferImageCopy,
				len(copy.regions),
				G_RENDERER_ALLOCATORS.temp_allocator,
			)
			defer delete(vk_copies)

			for region, region_idx in copy.regions {

				vk_copies[region_idx].bufferOffset = vk.DeviceSize(region.buffer_offset)
				vk_copies[region_idx].imageSubresource = {
					aspectMask     = vk_map_image_aspect(region.subresource_range.aspect),
					baseArrayLayer = u32(region.subresource_range.base_layer),
					layerCount     = u32(region.subresource_range.layer_count),
					mipLevel       = u32(region.subresource_range.mip_level),
				}
				vk_copies[region_idx].imageExtent = {
					width  = image.desc.dimensions[0] << region.subresource_range.mip_level,
					height = image.desc.dimensions[1] << region.subresource_range.mip_level,
					depth  = 1,
				}
			}

			vk.CmdPipelineBarrier(
				cmd_buff.cmd_buff,
				{.TOP_OF_PIPE},
				{.TRANSFER},
				nil,
				0,
				nil,
				0,
				nil,
				u32(num_placed_barries),
				&image_barriers[0],
			)

			vk.CmdCopyBufferToImage(
				cmd_buff.cmd_buff,
				buffer.vk_buffer,
				image.vk_image,
				.TRANSFER_DST_OPTIMAL,
				u32(len(vk_copies)),
				raw_data(vk_copies),
			)
		}
	}

	//---------------------------------------------------------------------------//


}
