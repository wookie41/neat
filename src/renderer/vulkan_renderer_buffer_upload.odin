package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		transfer_fences: []vk.Fence,
		had_requests_prev_frame: bool,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_begin_frame :: proc() {
		if !INTERNAL.had_requests_prev_frame {
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
				   ) != .SUCCESS {
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

		cmd_buff_ref := get_frame_cmd_buffer()
		cmd_buff := get_command_buffer(cmd_buff_ref)

		staging_buff := get_buffer(p_staging_buffer_ref)

		for request in p_upload_requests {
			dst_buffer := get_buffer(request.dst_buff)
			// @TODO Group buffers by dst_buffer so we can issue one CmdCopyBuffer with multiple regions
			region := vk.BufferCopy {
				srcOffset = vk.DeviceSize(request.staging_buffer_offset),
				dstOffset = vk.DeviceSize(request.dst_buff_offset),
				size      = vk.DeviceSize(request.size),
			}
			vk.CmdCopyBuffer(
				cmd_buff.vk_cmd_buff,
				staging_buff.vk_buffer,
				dst_buffer.vk_buffer,
				1,
				&region,
			)
			// Issue the barrier based on the usage declared by the request
			dst_stages := vk.PipelineStageFlags{}
			dst_stages += {backend_map_pipeline_stage(request.first_usage_stage)}

			access_mask := vk.AccessFlags{}
			if .VertexBuffer in dst_buffer.desc.usage {
				access_mask = {.VERTEX_ATTRIBUTE_READ}
			} else if .IndexBuffer in dst_buffer.desc.usage {
				access_mask = {.INDEX_READ}
			} else if .UniformBuffer in dst_buffer.desc.usage {
				access_mask = {.UNIFORM_READ}
			} else if .Storagebuffer in dst_buffer.desc.usage {
				access_mask = {.SHADER_READ}
			} else {
				// You shouldn't be here, uploading to this buffer is not supported at the moment
				assert(false)
			}

			// @TODO For now, using the graphics queue for transfer, so synchronization is easer
			buffer_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(request.size),
				offset = vk.DeviceSize(request.dst_buff_offset),
				buffer = dst_buffer.vk_buffer,
				dstAccessMask = access_mask,
				srcAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			}

			vk.CmdPipelineBarrier(
				cmd_buff.vk_cmd_buff,
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

		vk.ResetFences(G_RENDERER.device, 1, &INTERNAL.transfer_fences[get_frame_idx()])
	}
	//---------------------------------------------------------------------------//
}
