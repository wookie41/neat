package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"
	import "core:log"

	//---------------------------------------------------------------------------//

	@(private)
	BackendCommandBufferResource :: struct {
		vk_cmd_buff: vk.CommandBuffer,
	}

	//---------------------------------------------------------------------------//


	@(private = "file")
	INTERNAL: struct {
		command_pools: []vk.CommandPool,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_command_buffers :: proc(p_options: InitOptions) -> bool {

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

	@(private)
	backend_create_command_buffer :: proc(
		p_cmd_buff_desc: CommandBufferDesc,
		p_cmd_buff: ^CommandBufferResource, 
	) -> bool {
		alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = INTERNAL.command_pools[p_cmd_buff_desc.frame],
			level              = .PRIMARY if .Primary in p_cmd_buff_desc.flags else .SECONDARY,
			commandBufferCount = 1,
		}

		if vk.AllocateCommandBuffers(
			   G_RENDERER.device,
			   &alloc_info,
			   &p_cmd_buff.vk_cmd_buff,
		   ) != .SUCCESS {
			return false
		}

		return true
	}
	//---------------------------------------------------------------------------//
}
