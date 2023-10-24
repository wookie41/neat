package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		transfer_fences:         []vk.Fence,
		had_requests_prev_frame: bool,
	}

	//---------------------------------------------------------------------------//


	@(private)
	backend_buffer_upload_begin_frame :: proc() {
		if !INTERNAL.had_requests_prev_frame ||
		   G_RENDERER.queue_family_transfer_index == G_RENDERER.queue_family_graphics_index {
			return
		}

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
	backend_run_buffer_upload_requests :: proc(
		p_staging_buffer_ref: BufferRef,
		p_upload_requests: [dynamic]PendingBufferUploadRequest,
	) {

		if len(p_upload_requests) == 0 {
			INTERNAL.had_requests_prev_frame = false
			return
		}

		INTERNAL.had_requests_prev_frame = true
		transfer_cmd_buff := get_frame_transfer_cmd_buffer()

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			begin_info := vk.CommandBufferBeginInfo {
				sType = .COMMAND_BUFFER_BEGIN_INFO,
				flags = {.ONE_TIME_SUBMIT},
			}
			vk.BeginCommandBuffer(transfer_cmd_buff, &begin_info)
		}

		backend_staging_buff := &g_resources.backend_buffers[get_buffer_idx(p_staging_buffer_ref)]

		for request in p_upload_requests {
			dst_buffer := &g_resources.buffers[get_buffer_idx(request.dst_buff)]
			backend_dst_buffer := &g_resources.backend_buffers[get_buffer_idx(request.dst_buff)]

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

			dst_stages := vk.PipelineStageFlags{}
			dst_stages += {backend_map_pipeline_stage(request.first_usage_stage)}

			// Issue an acquire barrier for the dst buffer if we're using a dedicated transfer queue
			is_not_first_usage := backend_dst_buffer.owning_queue_family_idx != max(u32)
			not_owning_buffer :=
				backend_dst_buffer.owning_queue_family_idx !=
				G_RENDERER.queue_family_transfer_index
			if (is_not_first_usage && not_owning_buffer) &&
			   .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				acquire_barrier := vk.BufferMemoryBarrier {
					sType = .BUFFER_MEMORY_BARRIER,
					pNext = nil,
					size = vk.DeviceSize(request.size),
					offset = vk.DeviceSize(request.dst_buff_offset),
					buffer = backend_dst_buffer.vk_buffer,
					dstAccessMask = {.TRANSFER_WRITE},
					srcQueueFamilyIndex = G_RENDERER.queue_family_graphics_index,
					dstQueueFamilyIndex = G_RENDERER.queue_family_transfer_index,
				}

				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.BOTTOM_OF_PIPE},
					{.TRANSFER},
					nil,
					0,
					nil,
					1,
					&acquire_barrier,
					0,
					nil,
				)
			}

			// @TODO Group buffers by dst_buffer so we can issue one CmdCopyBuffer with multiple regions

			// Run the copy
			region := vk.BufferCopy {
				srcOffset = vk.DeviceSize(request.staging_buffer_offset),
				dstOffset = vk.DeviceSize(request.dst_buff_offset),
				size      = vk.DeviceSize(request.size),
			}
			vk.CmdCopyBuffer(
				transfer_cmd_buff,
				backend_staging_buff.vk_buffer,
				backend_dst_buffer.vk_buffer,
				1,
				&region,
			)

			buffer_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(request.size),
				offset = vk.DeviceSize(request.dst_buff_offset),
				buffer = backend_dst_buffer.vk_buffer,
				srcAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			}

			// Issue a release barrier for the dst buffer if we're using a dedicated transfer queue
			if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				// @TODO This should check to which queue this buffer belongs to hand back
				// ownership to the appropriate queue
				graphics_cmd_buff_ref := get_frame_cmd_buffer()
				graphics_cmd_buff := get_command_buffer(graphics_cmd_buff_ref).vk_cmd_buff

				buffer_barrier.srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index
				buffer_barrier.dstQueueFamilyIndex = G_RENDERER.queue_family_graphics_index

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

		// Now we have to submit the transfer if we're using a dedicated transfer queue
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
