package renderer

//---------------------------------------------------------------------------//

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		transfer_fences: []vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_wait_for_transfers :: proc() {
		// Make sure that the GPU is no longer reading the current staging buffer region
		vk.WaitForFences(
			G_RENDERER.device,
			1,
			&INTERNAL.transfer_fences[get_frame_idx()],
			true,
			max(u64),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_buffer_upload :: proc(p_options: BufferUploadInitOptions) -> bool {
		INTERNAL.transfer_fences = make(
			[]vk.Fence,
			int(p_options.num_staging_regions),
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		// Create the fences used to make sure the we can safely fill the buffer from the CPU side
		{
			fence_create_info := vk.FenceCreateInfo {
				sType = .FENCE_CREATE_INFO,
				flags = {.SIGNALED},
				pNext = nil,
			}

			for i in 0 ..< p_options.num_staging_regions {
				if vk.CreateFence(
					   G_RENDERER.device,
					   &fence_create_info,
					   nil,
					   &INTERNAL.transfer_fences[i],
				   ) !=
				   .SUCCESS {
					// Not bothering to destroy the already created fences here, as we'll shutdown the application
					return false
				}
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_pre_frame_submit :: proc(
		p_requests: map[BufferRef][dynamic]PendingBufferUploadRequest,
	) {
		// Release the buffers on the src queue when using a dedicated transfer queue
		if (.DedicatedTransferQueue in G_RENDERER.gpu_device_flags) == false {
			return
		}

		for buffer_ref, _ in p_requests {

			buffer := &g_resources.buffers[get_buffer_idx(buffer_ref)]
			backend_buffer := &g_resources.backend_buffers[get_buffer_idx(buffer_ref)]

			src_cmd_buffer :=
				g_resources.backend_cmd_buffers[get_cmd_buffer_idx(get_frame_cmd_buffer_ref())].vk_cmd_buff

			src_queue := vk.QUEUE_FAMILY_IGNORED

			is_not_first_usage := backend_buffer.owning_queue_family_idx != max(u32)
			not_owning_buffer :=
				backend_buffer.owning_queue_family_idx != G_RENDERER.queue_family_transfer_index

			if is_not_first_usage && not_owning_buffer {
				src_queue = backend_buffer.owning_queue_family_idx

				if src_queue == G_RENDERER.queue_family_compute_index {
					src_cmd_buffer = get_frame_compute_cmd_buffer()
				}
			}


			buffer_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(buffer.desc.size),
				offset = 0,
				buffer = backend_buffer.vk_buffer,
				dstAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = src_queue,
				dstQueueFamilyIndex = G_RENDERER.queue_family_transfer_index,
			}

			// Release barrier
			vk.CmdPipelineBarrier(
				src_cmd_buffer,
				{.BOTTOM_OF_PIPE},
				{.TRANSFER},
				nil,
				0,
				nil,
				1,
				&buffer_barrier,
				0,
				nil,
			)

		}
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_run_buffer_upload_requests :: proc(
		p_staging_buffer_ref: BufferRef,
		p_upload_requests: ^map[BufferRef][dynamic]PendingBufferUploadRequest,
	) {

		transfer_cmd_buff := get_frame_transfer_cmd_buffer()

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			begin_info := vk.CommandBufferBeginInfo {
				sType = .COMMAND_BUFFER_BEGIN_INFO,
				flags = {.ONE_TIME_SUBMIT},
			}
			vk.BeginCommandBuffer(transfer_cmd_buff, &begin_info)
		}

		for dst_buffer_ref, requests in p_upload_requests {

			temp_arena := common.TempArena{}
			common.temp_arena_init(&temp_arena)
			defer common.temp_arena_delete(temp_arena)
			
			dst_buffer := &g_resources.buffers[get_buffer_idx(dst_buffer_ref)]
			backend_dst_buffer := &g_resources.backend_buffers[get_buffer_idx(dst_buffer_ref)]

			// Acquire barrier for the dst buffer if we're using a dedicated transfer queue
			is_not_first_usage := backend_dst_buffer.owning_queue_family_idx != max(u32)
			not_owning_buffer :=
				backend_dst_buffer.owning_queue_family_idx !=
				G_RENDERER.queue_family_transfer_index

			src_queue := vk.QUEUE_FAMILY_IGNORED

			if (is_not_first_usage && not_owning_buffer) &&
			   .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				src_queue = backend_dst_buffer.owning_queue_family_idx

				buffer_barrier := vk.BufferMemoryBarrier {
					sType = .BUFFER_MEMORY_BARRIER,
					pNext = nil,
					size = vk.DeviceSize(dst_buffer.desc.size),
					offset = 0,
					buffer = backend_dst_buffer.vk_buffer,
					dstAccessMask = {.TRANSFER_WRITE},
					srcQueueFamilyIndex = src_queue,
					dstQueueFamilyIndex = G_RENDERER.queue_family_transfer_index,
				}

				// Acquire barrier
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.BOTTOM_OF_PIPE},
					{.TRANSFER},
					nil,
					0,
					nil,
					1,
					&buffer_barrier,
					0,
					nil,
				)
			}

			access_mask := vk.AccessFlags{}
			if .VertexBuffer in dst_buffer.desc.usage {
				access_mask = {.VERTEX_ATTRIBUTE_READ}
			} else if .IndexBuffer in dst_buffer.desc.usage {
				access_mask = {.INDEX_READ}
			} else if .UniformBuffer in dst_buffer.desc.usage {
				access_mask = {.UNIFORM_READ}
			} else if .StorageBuffer in dst_buffer.desc.usage {
				access_mask = {.SHADER_READ}
			} else {
				// You shouldn't be here, uploading to this buffer is not supported at the moment
				assert(false)
			}


			// Gather all stages that the buffer will be used in after the requests and create vk buffer copies
			dst_stages := vk.PipelineStageFlags{}
			buffer_copies := make([]vk.BufferCopy, len(requests), temp_arena.allocator)
			for request, i in requests {
				dst_stages += {backend_map_pipeline_stage(request.first_usage_stage)}
				buffer_copies[i] = vk.BufferCopy {
					srcOffset = vk.DeviceSize(request.staging_buffer_offset),
					dstOffset = vk.DeviceSize(request.dst_buff_offset),
					size      = vk.DeviceSize(request.size),
				}
			}

			backend_staging_buff := &g_resources.backend_buffers[get_buffer_idx(p_staging_buffer_ref)]

			// Run the copies
			vk.CmdCopyBuffer(
				transfer_cmd_buff,
				backend_staging_buff.vk_buffer,
				backend_dst_buffer.vk_buffer,
				u32(len(buffer_copies)),
				raw_data(buffer_copies),
			)

			buffer_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(dst_buffer.desc.size),
				offset = 0,
				buffer = backend_dst_buffer.vk_buffer,
				srcAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			}

			// If the buffer wasn't originally owned by any queue, then put in on the graphics queue
			if src_queue == vk.QUEUE_FAMILY_IGNORED {
				src_queue = G_RENDERER.queue_family_graphics_index
			}

			// Issue a release barrier for the dst buffer if we're using a dedicated transfer queue
			if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				buffer_barrier.srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index
				buffer_barrier.dstQueueFamilyIndex = src_queue

				backend_dst_buffer.owning_queue_family_idx = src_queue

				// Release from transfer...
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.TRANSFER},
					{.TOP_OF_PIPE},
					nil,
					0,
					nil,
					1,
					&buffer_barrier,
					0,
					nil,
				)

				src_cmd_buffer :=
					g_resources.backend_cmd_buffers[get_cmd_buffer_idx(get_frame_cmd_buffer_ref())].vk_cmd_buff

				if is_not_first_usage && not_owning_buffer {
					if src_queue == G_RENDERER.queue_family_compute_index {
						src_cmd_buffer = get_frame_compute_cmd_buffer()
					}
				}

				// ... and acquire on the original queue
				vk.CmdPipelineBarrier(
					src_cmd_buffer,
					{.TRANSFER},
					{.TOP_OF_PIPE},
					nil,
					0,
					nil,
					1,
					&buffer_barrier,
					0,
					nil,
				)

			} else {
				// Otherwise issue a standard memory barrier
				buffer_barrier.dstAccessMask = access_mask
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.TRANSFER},
					dst_stages,
					nil,
					0,
					nil,
					1,
					&buffer_barrier,
					0,
					nil,
				)
			}
		}

		// Submit the transfer if we're using a dedicated transfer queue
		// Otherwise it'll be executed as part of the normal command buffer
		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

			G_RENDERER.should_wait_on_transfer_semaphore = true

			vk.ResetFences(G_RENDERER.device, 1, &INTERNAL.transfer_fences[get_frame_idx()])

			vk.EndCommandBuffer(transfer_cmd_buff)

			submit_info := vk.SubmitInfo {
				sType                = .SUBMIT_INFO,
				commandBufferCount   = 1,
				pCommandBuffers      = &transfer_cmd_buff,
				signalSemaphoreCount = 1,
				pSignalSemaphores    = &G_RENDERER.transfer_finished_semaphores[get_frame_idx()],
			}

			vk.QueueSubmit(
				G_RENDERER.transfer_queue,
				1,
				&submit_info,
				INTERNAL.transfer_fences[get_frame_idx()],
			)
		}
	}
	//---------------------------------------------------------------------------//
}
