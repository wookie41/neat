package renderer

//---------------------------------------------------------------------------//

import "core:log"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	BackendCommandBufferResource :: struct {
		vk_cmd_buff: vk.CommandBuffer,
	}

	//---------------------------------------------------------------------------//


	@(private = "file")
	INTERNAL: struct {
		graphics_command_pools:             []vk.CommandPool,
		transfer_command_pools:             []vk.CommandPool,
		compute_command_pools:              []vk.CommandPool,
		transfer_cmd_buffers_pre_graphics:  []vk.CommandBuffer,
		transfer_cmd_buffers_post_graphics: []vk.CommandBuffer,
		compute_cmd_buffers:                []vk.CommandBuffer,
		immediate_submit_command_pool:      vk.CommandPool,
		immediate_submit_cmd_buffer:        vk.CommandBuffer,
		immediate_submit_fence:             vk.Fence,
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
			true,
			INTERNAL.graphics_command_pools,
			nil,
		) or_return

		// Create command pools for transfer queue if the GPU has a dedicated one
		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			INTERNAL.transfer_command_pools = make(
				[]vk.CommandPool,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			INTERNAL.transfer_cmd_buffers_pre_graphics = make(
				[]vk.CommandBuffer,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			INTERNAL.transfer_cmd_buffers_post_graphics = make(
				[]vk.CommandBuffer,
				int(G_RENDERER.num_frames_in_flight),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			create_command_pools(
				u32(G_RENDERER.queue_family_transfer_index),
				true,
				true,
				INTERNAL.transfer_command_pools,
				INTERNAL.transfer_cmd_buffers_pre_graphics,
			) or_return

			create_command_pools(
				u32(G_RENDERER.queue_family_transfer_index),
				true,
				false,
				INTERNAL.transfer_command_pools,
				INTERNAL.transfer_cmd_buffers_post_graphics,
			) or_return
		}

		// Create command pools for compute queue if the GPU has a dedicated one
		if .DedicatedComputeQueue in G_RENDERER.gpu_device_flags {
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
				true,
				INTERNAL.compute_command_pools,
				INTERNAL.compute_cmd_buffers,
			) or_return
		}


		// Create the command pool for immediate submit
		{
			cmd_pool_create_info := vk.CommandPoolCreateInfo {
				sType = .COMMAND_POOL_CREATE_INFO,
				flags = {.RESET_COMMAND_BUFFER},
				queueFamilyIndex = G_RENDERER.queue_family_graphics_index,
			}
			if vk.CreateCommandPool(
				   G_RENDERER.device,
				   &cmd_pool_create_info,
				   nil,
				   &INTERNAL.immediate_submit_command_pool,
			   ) !=
			   .SUCCESS {
				return false
			}

			alloc_info := vk.CommandBufferAllocateInfo {
				sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
				commandBufferCount = 1,
				commandPool        = INTERNAL.immediate_submit_command_pool,
				level              = .PRIMARY,
			}
			if vk.AllocateCommandBuffers(
				   G_RENDERER.device,
				   &alloc_info,
				   &INTERNAL.immediate_submit_cmd_buffer,
			   ) !=
			   .SUCCESS {
				return false
			}

			fence_create_info := vk.FenceCreateInfo {
				sType = .FENCE_CREATE_INFO,
			}
			vk.CreateFence(
				G_RENDERER.device,
				&fence_create_info,
				nil,
				&INTERNAL.immediate_submit_fence,
			)
		}

		return true
	}


	@(private = "file")
	create_command_pools :: proc(
		p_queue_family_idx: u32,
		p_allocate_command_buffers: bool,
		p_create_command_pools: bool,
		p_cmd_pools: []vk.CommandPool,
		p_cmd_buffers: []vk.CommandBuffer,
	) -> bool {

		if p_create_command_pools {
			pool_info := vk.CommandPoolCreateInfo {
				sType = .COMMAND_POOL_CREATE_INFO,
				queueFamilyIndex = p_queue_family_idx,
				flags = {.RESET_COMMAND_BUFFER},
			}

			for i in 0 ..< G_RENDERER.num_frames_in_flight {
				if vk.CreateCommandPool(G_RENDERER.device, &pool_info, nil, &p_cmd_pools[i]) !=
				   .SUCCESS {
					log.error("Couldn't create command pool")
					return false
				}
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

				if vk.AllocateCommandBuffers(G_RENDERER.device, &alloc_info, &p_cmd_buffers[i]) !=
				   .SUCCESS {
					return false
				}

			}
		}
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_command_buffer :: proc(p_ref: CommandBufferRef) -> bool {
		cmd_buffer_idx := get_cmd_buffer_idx(p_ref)
		cmd_buffer := &g_resources.cmd_buffers[cmd_buffer_idx]
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[cmd_buffer_idx]

		alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = INTERNAL.graphics_command_pools[cmd_buffer.desc.frame],
			level              = .PRIMARY if .Primary in cmd_buffer.desc.flags else .SECONDARY,
			commandBufferCount = 1,
		}

		if vk.AllocateCommandBuffers(
			   G_RENDERER.device,
			   &alloc_info,
			   &backend_cmd_buffer.vk_cmd_buff,
		   ) !=
		   .SUCCESS {
			return false
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_begin_command_buffer :: proc(p_ref: CommandBufferRef) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_ref)]

		begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
			flags = {.ONE_TIME_SUBMIT},
		}

		vk.BeginCommandBuffer(backend_cmd_buffer.vk_cmd_buff, &begin_info)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_end_command_buffer :: proc(p_ref: CommandBufferRef) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_ref)]
		vk.EndCommandBuffer(backend_cmd_buffer.vk_cmd_buff)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_command_buffer :: proc(p_ref: CommandBufferRef) {
		cmd_buffer_idx := get_cmd_buffer_idx(p_ref)
		cmd_buffer := &g_resources.cmd_buffers[cmd_buffer_idx]
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[cmd_buffer_idx]

		vk.FreeCommandBuffers(
			G_RENDERER.device,
			INTERNAL.graphics_command_pools[cmd_buffer.desc.thread],
			1,
			&backend_cmd_buffer.vk_cmd_buff,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	get_frame_transfer_cmd_buffer_pre_graphics :: proc() -> vk.CommandBuffer {
		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			return INTERNAL.transfer_cmd_buffers_pre_graphics[get_frame_idx()]
		}
		cmd_buff_ref := get_frame_cmd_buffer_ref()
		return g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buff_ref)].vk_cmd_buff
	}

	//---------------------------------------------------------------------------//

	@(private)
	get_frame_transfer_cmd_buffer_post_graphics :: proc() -> vk.CommandBuffer {
		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			return INTERNAL.transfer_cmd_buffers_post_graphics[get_frame_idx()]
		}
		cmd_buff_ref := get_frame_cmd_buffer_ref()
		return g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buff_ref)].vk_cmd_buff
	}

	//---------------------------------------------------------------------------//

	@(private)
	get_frame_compute_cmd_buffer :: proc() -> vk.CommandBuffer {
		if .DedicatedComputeQueue in G_RENDERER.gpu_device_flags {
			return INTERNAL.compute_cmd_buffers[get_frame_idx()]
		}
		cmd_buff_ref := get_frame_cmd_buffer_ref()
		return g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buff_ref)].vk_cmd_buff
	}


	//---------------------------------------------------------------------------//
}

@(private)
command_buffer_one_time_submit :: proc(p_function: proc(p_cmd_buff: vk.CommandBuffer)) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(INTERNAL.immediate_submit_cmd_buffer, &begin_info)
	p_function(INTERNAL.immediate_submit_cmd_buffer)
	vk.EndCommandBuffer(INTERNAL.immediate_submit_cmd_buffer)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &INTERNAL.immediate_submit_cmd_buffer,
	}

	vk.QueueSubmit(G_RENDERER.graphics_queue, 1, &submit_info, INTERNAL.immediate_submit_fence)
	vk.WaitForFences(G_RENDERER.device, 1, &INTERNAL.immediate_submit_fence, true, 9999999999)
	vk.ResetFences(G_RENDERER.device, 1, &INTERNAL.immediate_submit_fence)
	vk.ResetCommandPool(G_RENDERER.device, INTERNAL.immediate_submit_command_pool, nil)
}
