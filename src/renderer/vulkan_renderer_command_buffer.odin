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
		p_cmd_buff: CommandBufferEntry,
		p_copy: BufferImageCopy,
	) {

        // TODO batch them
        image := get_image(p_copy.image)
        buffer := get_buffer(p_copy.buffer)
        cmd_buff := INTERNAL.command_buffers[u32(p_cmd_buff)]

        copy := vk.BufferImageCopy {
            bufferOffset = vk.DeviceSize(p_copy.buffer_offset),
            imageSubresource = {
                aspectMask = vk_map_image_aspect(p_copy.subresource_range.aspect),
                baseArrayLayer = p_copy.subresource_range.base_layer,
                layerCount = p_copy.subresource_range.layer_count,
                baseMipLevel = p_copy.subresource_range.base_mip,
                mipLevel = p_copy.subresource_range.mip_count,
            },
            imageExtent = {
                width = image.desc.dimensions[0] << p_copy.subresource_range.base_mip,
                height = image.desc.dimensions[1] << p_copy.subresource_range.base_mip,
                depth = 1,
            },
        }

        vk.CmdCopyBufferToImage(cmd_buff.cmd_buff, buffer.vk_buffer, image.vk_image, .TRANSFER_DST_OPTIMAL, 0, )

	}

	//---------------------------------------------------------------------------//


}
