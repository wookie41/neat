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


	@(private)
	INTERNAL: struct {
		graphics_command_pools: []vk.CommandPool,
		transfer_command_pools: []vk.CommandPool,
		compute_command_pools:  []vk.CommandPool,

		transfer_cmd_buffers: []vk.CommandBuffer,
		compute_cmd_buffers: []vk.CommandBuffer,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_command_buffers :: proc(p_options: InitOptions) -> bool {

		// Create graphics command pools
		INTERNAL.graphics_command_pools = make(
			[]vk.CommandPool,
			int(G_RENDERER.num_frames_in_flight),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		create_command_pools(
			u32(G_RENDERER.queue_family_graphics_index),
			false,
			INTERNAL.graphics_command_pools,
			nil,
		) or_return

		// Create command pools for transfer queue if the GPU has a dedicated one
		if G_RENDERER.queue_family_transfer_index != G_RENDERER.queue_family_graphics_index {
			INTERNAL.transfer_command_pools = make(
				[]vk.CommandPool,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			INTERNAL.transfer_cmd_buffers = make(
				[]vk.CommandBuffer,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			create_command_pools(
				u32(G_RENDERER.queue_family_transfer_index),
				true,
				INTERNAL.transfer_command_pools,
				INTERNAL.transfer_cmd_buffers,
			) or_return
		}

		// Create command pools for compute queue if the GPU has a dedicated one
		if G_RENDERER.queue_family_transfer_index != G_RENDERER.queue_family_graphics_index {
			INTERNAL.compute_command_pools = make(
				[]vk.CommandPool,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			INTERNAL.compute_cmd_buffers = make(
				[]vk.CommandBuffer,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			create_command_pools(
				u32(G_RENDERER.queue_family_compute_index),
				true,
				INTERNAL.compute_command_pools,
				INTERNAL.compute_cmd_buffers,
			) or_return
		}

		return true
	}


	@(private = "file")
	create_command_pools :: proc(
		p_queue_family_idx: u32,
		p_allocate_command_buffers: bool,
		p_cmd_pools: []vk.CommandPool,
		p_cmd_buffers: []vk.CommandBuffer,
	) -> bool {

		pool_info := vk.CommandPoolCreateInfo {
			sType = .COMMAND_POOL_CREATE_INFO,
			queueFamilyIndex = p_queue_family_idx,
			flags = {.RESET_COMMAND_BUFFER},
		}

		for i in 0 ..< G_RENDERER.num_frames_in_flight {
			if vk.CreateCommandPool(G_RENDERER.device, &pool_info, nil, &p_cmd_pools[i]) != .SUCCESS {
				log.error("Couldn't create command pool")
				return false
			}
		}

		if p_allocate_command_buffers {
			for cmd_pool, i in p_cmd_pools {
				alloc_info := vk.CommandBufferAllocateInfo {
					sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
					commandPool        = cmd_pool,
					level              = .PRIMARY,
					commandBufferCount = 1,
				}

				if vk.AllocateCommandBuffers(
					   G_RENDERER.device,
					   &alloc_info,
					   &p_cmd_buffers[i],
				   ) != .SUCCESS {
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
			commandPool        = INTERNAL.graphics_command_pools[p_cmd_buff_desc.frame],
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

	@(private)
	backend_begin_command_buffer :: proc(
		p_ref: CommandBufferRef,
		p_cmd_buff: ^CommandBufferResource,
	) {

		begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
			flags = {.ONE_TIME_SUBMIT},
		}

		vk.BeginCommandBuffer(p_cmd_buff.vk_cmd_buff, &begin_info)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_end_command_buffer :: proc(
		p_ref: CommandBufferRef,
		p_cmd_buff: ^CommandBufferResource,
	) {
		vk.EndCommandBuffer(p_cmd_buff.vk_cmd_buff)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_command_buffer :: proc(p_cmd_buff: ^CommandBufferResource) {
		vk.FreeCommandBuffers(
			G_RENDERER.device,
			INTERNAL.graphics_command_pools[p_cmd_buff.desc.thread],
			1,
			&p_cmd_buff.vk_cmd_buff,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	get_frame_transfer_cmd_buffer :: proc() -> vk.CommandBuffer {
		if G_RENDERER.queue_family_transfer_index != G_RENDERER.queue_family_graphics_index {
			return INTERNAL.transfer_cmd_buffers[get_frame_idx()]
		}
		cmd_buff_ref := get_frame_cmd_buffer()
		return get_command_buffer(cmd_buff_ref).vk_cmd_buff
	}


	//---------------------------------------------------------------------------//
}
