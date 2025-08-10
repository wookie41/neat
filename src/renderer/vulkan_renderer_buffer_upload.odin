package renderer

//---------------------------------------------------------------------------//

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		finished_transfer_infos: [dynamic]FinishedTransferInfo,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	FinishedTransferInfo :: struct {
		dst_buffer_ref:                  BufferRef,
		size:                            u32,
		offset:                          u32,
		post_transfer_stage:             PipelineStageFlagBits,
		post_transfer_queue_family_idx:  u32,
		async_upload_callback_user_data: rawptr,
		async_upload_finished_callback:  proc(p_user_data: rawptr),
		fence_idx:                       u8,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_wait_for_transfer_resources :: proc() {
		// Make sure that the GPU is no longer reading the current staging buffer region
		fences := []vk.Fence{
			G_RENDERER.transfer_fences_pre_graphics[get_frame_idx()],
			G_RENDERER.transfer_fences_post_graphics[get_frame_idx()],
		}
		vk.WaitForFences(G_RENDERER.device, u32(len(fences)), &fences[0], true, max(u64))
		vk.ResetFences(G_RENDERER.device, u32(len(fences)), &fences[0])
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_finalize_finished_uploads :: proc() {

		if len(INTERNAL.finished_transfer_infos) == 0 {
			return
		}

		transfer_cmd_buff := frame_transfer_cmd_buffer_pre_graphics_get()
		finished_transfer_infos := make([dynamic]FinishedTransferInfo, get_next_frame_allocator())

		for finished_transfer_info in &INTERNAL.finished_transfer_infos {

			upload_done_fence :=
				G_RENDERER.transfer_fences_post_graphics[finished_transfer_info.fence_idx]

			if vk.GetFenceStatus(G_RENDERER.device, upload_done_fence) != .SUCCESS {
				append(&finished_transfer_infos, finished_transfer_info)
				continue
			}

			// Issue release/acquire barriers
			dst_buffer_idx := buffer_get_idx(finished_transfer_info.dst_buffer_ref)
			backend_dst_buffer := &g_resources.backend_buffers[dst_buffer_idx]

			src_cmd_buffer_ref := get_frame_cmd_buffer_ref()
			src_cmd_buffer :=
				g_resources.backend_cmd_buffers[command_buffer_get_idx(src_cmd_buffer_ref)].vk_cmd_buff

			if finished_transfer_info.post_transfer_queue_family_idx ==
			   G_RENDERER.queue_family_compute_index {
				src_cmd_buffer = frame_compute_cmd_buffer_get()
			}

			release_acquire_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(finished_transfer_info.size),
				offset = vk.DeviceSize(finished_transfer_info.offset),
				buffer = backend_dst_buffer.vk_buffer,
				srcAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index,
				dstQueueFamilyIndex = finished_transfer_info.post_transfer_queue_family_idx,
			}

			// Release
			vk.CmdPipelineBarrier(
				transfer_cmd_buff,
				{.TRANSFER},
				{.TOP_OF_PIPE},
				nil,
				0,
				nil,
				1,
				&release_acquire_barrier,
				0,
				nil,
			)


			// Acquire
			vk.CmdPipelineBarrier(
				src_cmd_buffer,
				{.TRANSFER},
				{.TOP_OF_PIPE},
				nil,
				0,
				nil,
				1,
				&release_acquire_barrier,
				0,
				nil,
			)

			if finished_transfer_info.async_upload_finished_callback != nil {
				finished_transfer_info.async_upload_finished_callback(
					finished_transfer_info.async_upload_callback_user_data,
				)
			}
		}

		INTERNAL.finished_transfer_infos = finished_transfer_infos
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_init :: proc(p_options: BufferUploadInitOptions) -> bool {
		G_RENDERER.transfer_fences_pre_graphics = make(
			[]vk.Fence,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.main_allocator,
		)
		G_RENDERER.transfer_fences_post_graphics = make(
			[]vk.Fence,
			G_RENDERER.num_frames_in_flight,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		INTERNAL.finished_transfer_infos = make(
			[dynamic]FinishedTransferInfo,
			get_frame_allocator(),
		)

		// Create the fences used to make sure the we can safely fill the buffer from the CPU side
		{
			fence_create_info := vk.FenceCreateInfo {
				sType = .FENCE_CREATE_INFO,
				flags = {.SIGNALED},
				pNext = nil,
			}

			for i in 0 ..< G_RENDERER.num_frames_in_flight {
				if vk.CreateFence(
					   G_RENDERER.device,
					   &fence_create_info,
					   nil,
					   &G_RENDERER.transfer_fences_pre_graphics[i],
				   ) !=
				   .SUCCESS {
					// Not bothering to destroy the already created fences here, as we'll shutdown the application
					return false
				}

				if vk.CreateFence(
					   G_RENDERER.device,
					   &fence_create_info,
					   nil,
					   &G_RENDERER.transfer_fences_post_graphics[i],
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
	backend_buffer_upload_start_async_cmd_buffer_pre_graphics :: proc() {
		transfer_cmd_buff_pre_graphics := frame_transfer_cmd_buffer_pre_graphics_get()
		begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
			flags = {.ONE_TIME_SUBMIT},
		}
		vk.BeginCommandBuffer(transfer_cmd_buff_pre_graphics, &begin_info)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_start_async_cmd_buffer_post_graphics :: proc() {
		transfer_cmd_buff_post_graphics := frame_transfer_cmd_buffer_post_graphics_get()
		begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
			flags = {.ONE_TIME_SUBMIT},
		}
		vk.BeginCommandBuffer(transfer_cmd_buff_post_graphics, &begin_info)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_run_buffer_upload_requests :: proc(
		p_staging_buffer_ref: BufferRef,
		p_dst_buffer_ref: BufferRef,
		p_pending_requests: [dynamic]PendingBufferUploadRequest,
	) {
		temp_arena := common.Arena{}
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		dst_buffer_idx := buffer_get_idx(p_dst_buffer_ref)
		dst_buffer := &g_resources.buffers[dst_buffer_idx]
		backend_dst_buffer := &g_resources.backend_buffers[dst_buffer_idx]

		access_mask := vk.AccessFlags{}
		if .VertexBuffer in dst_buffer.desc.usage {
			access_mask = {.VERTEX_ATTRIBUTE_READ}
		} else if .IndexBuffer in dst_buffer.desc.usage {
			access_mask = {.INDEX_READ}
		} else if .UniformBuffer in dst_buffer.desc.usage ||
		   .DynamicUniformBuffer in dst_buffer.desc.usage {
			access_mask = {.UNIFORM_READ}
		} else if .StorageBuffer in dst_buffer.desc.usage ||
		   .DynamicStorageBuffer in dst_buffer.desc.usage {
			access_mask = {.SHADER_READ}
		} else {
			// You shouldn't be here, uploading to this buffer is not supported at the moment
			assert(false)
		}

		// Gather all stages that the buffer will be used in after the requests and create vk buffer copies
		dst_stages := vk.PipelineStageFlags{}
		buffer_copies := make([]vk.BufferCopy, len(p_pending_requests), temp_arena.allocator)
		for request, i in p_pending_requests {
			dst_stages += {backend_map_pipeline_stage(request.first_usage_stage)}
			buffer_copies[i] = vk.BufferCopy {
				srcOffset = vk.DeviceSize(request.staging_buffer_offset),
				dstOffset = vk.DeviceSize(request.dst_buff_offset),
				size      = vk.DeviceSize(request.size),
			}
		}

		backend_staging_buff := &g_resources.backend_buffers[buffer_get_idx(p_staging_buffer_ref)]

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		backend_cmd_buff := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buffer_ref)]

		// Issue pre-copy barrier
		pre_upload_barrier := vk.BufferMemoryBarrier {
			sType = .BUFFER_MEMORY_BARRIER,
			pNext = nil,
			size = vk.DeviceSize(dst_buffer.desc.size),
			offset = 0,
			buffer = backend_dst_buffer.vk_buffer,
			dstAccessMask = {.TRANSFER_WRITE},
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		}

		vk.CmdPipelineBarrier(
			backend_cmd_buff.vk_cmd_buff,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			1,
			&pre_upload_barrier,
			0,
			nil,
		)
		// Run the copies
		vk.CmdCopyBuffer(
			backend_cmd_buff.vk_cmd_buff,
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
			dstAccessMask = access_mask,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		}

		// Issue a post copy memory barrier
		buffer_barrier.dstAccessMask = access_mask
		vk.CmdPipelineBarrier(
			backend_cmd_buff.vk_cmd_buff,
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
	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_submit_pre_graphics :: proc() {

		transfer_cmd_buff := frame_transfer_cmd_buffer_pre_graphics_get()
		vk.EndCommandBuffer(transfer_cmd_buff)

		submit_info := vk.SubmitInfo {
			sType              = .SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers    = &transfer_cmd_buff,
		}

		vk.QueueSubmit(
			G_RENDERER.transfer_queue,
			1,
			&submit_info,
			G_RENDERER.transfer_fences_pre_graphics[get_frame_idx()],
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_submit_post_graphics :: proc() {

		transfer_cmd_buff := frame_transfer_cmd_buffer_post_graphics_get()
		vk.EndCommandBuffer(transfer_cmd_buff)

		submit_info := vk.SubmitInfo {
			sType              = .SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers    = &transfer_cmd_buff,
		}

		vk.QueueSubmit(
			G_RENDERER.transfer_queue,
			1,
			&submit_info,
			G_RENDERER.transfer_fences_post_graphics[get_frame_idx()],
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_buffer_upload_run_sliced_sync :: proc(
		p_dst_buffer_ref: BufferRef,
		p_dst_buffer_offset: u32,
		p_src_buffer_ref: BufferRef,
		p_src_buffer_offset: u32,
		p_size_in_bytes: u32,
		p_post_transfer_stage: PipelineStageFlagBits,
		p_transfer_finished_callback: proc(p_user_data: rawptr),
		p_transfer_finished_user_data: rawptr,
		p_is_last_upload: bool,
		p_total_size: u32,
		p_base_offset: u32,
	) {

		cmd_buff_ref := get_frame_cmd_buffer_ref()
		backend_cmd_buff := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buff_ref)]

		dst_buffer_idx := buffer_get_idx(p_dst_buffer_ref)
		dst_buffer := &g_resources.buffers[dst_buffer_idx]
		backend_dst_buffer := &g_resources.backend_buffers[buffer_get_idx(p_dst_buffer_ref)]
		backend_src_buff := &g_resources.backend_buffers[buffer_get_idx(p_src_buffer_ref)]

		// Run the copy
		buffer_copy := vk.BufferCopy {
			srcOffset = vk.DeviceSize(p_src_buffer_offset),
			dstOffset = vk.DeviceSize(p_dst_buffer_offset),
			size      = vk.DeviceSize(p_size_in_bytes),
		}

		vk.CmdCopyBuffer(
			backend_cmd_buff.vk_cmd_buff,
			backend_src_buff.vk_buffer,
			backend_dst_buffer.vk_buffer,
			1,
			&buffer_copy,
		)

		// Determine access mask
		access_mask := vk.AccessFlags{}
		if .VertexBuffer in dst_buffer.desc.usage {
			access_mask = {.VERTEX_ATTRIBUTE_READ}
		} else if .IndexBuffer in dst_buffer.desc.usage {
			access_mask = {.INDEX_READ}
		} else if .UniformBuffer in dst_buffer.desc.usage ||
		   .DynamicUniformBuffer in dst_buffer.desc.usage {
			access_mask = {.UNIFORM_READ}
		} else if .StorageBuffer in dst_buffer.desc.usage ||
		   .DynamicStorageBuffer in dst_buffer.desc.usage {
			access_mask = {.SHADER_READ}
		} else {
			// You shouldn't be here, uploading to this buffer is not supported at the moment
			assert(false)
		}

		if p_is_last_upload {

			// Issue a post-copy barrier
			post_upload_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(p_size_in_bytes),
				offset = vk.DeviceSize(p_dst_buffer_offset),
				buffer = backend_dst_buffer.vk_buffer,
				srcAccessMask = {.TRANSFER_WRITE},
				dstAccessMask = access_mask,
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			}

			vk.CmdPipelineBarrier(
				backend_cmd_buff.vk_cmd_buff,
				{.TRANSFER},
				{backend_map_pipeline_stage(p_post_transfer_stage)},
				nil,
				0,
				nil,
				1,
				&post_upload_barrier,
				0,
				nil,
			)

			if p_transfer_finished_callback != nil {
				p_transfer_finished_callback(p_transfer_finished_user_data)
			}
		}
	}

	//---------------------------------------------------------------------------//


	@(private)
	backend_buffer_upload_run_sliced_async :: proc(
		p_dst_buffer_ref: BufferRef,
		p_dst_buffer_offset: u32,
		p_src_buffer_ref: BufferRef,
		p_src_buffer_offset: u32,
		p_size_in_bytes: u32,
		p_post_transfer_stage: PipelineStageFlagBits,
		p_transfer_finished_callback: proc(p_user_data: rawptr),
		p_transfer_finished_user_data: rawptr,
		p_is_last_upload: bool,
		p_total_size: u32,
		p_base_offset: u32,
	) {

		transfer_cmd_buff := frame_transfer_cmd_buffer_post_graphics_get()

		dst_buffer_idx := buffer_get_idx(p_dst_buffer_ref)
		backend_dst_buffer := &g_resources.backend_buffers[dst_buffer_idx]
		backend_src_buff := &g_resources.backend_buffers[buffer_get_idx(p_src_buffer_ref)]

		src_queue := backend_dst_buffer.owning_queue_family_idx

		src_cmd_buffer_ref := get_frame_cmd_buffer_ref()
		src_cmd_buffer :=
			g_resources.backend_cmd_buffers[command_buffer_get_idx(src_cmd_buffer_ref)].vk_cmd_buff

		if src_queue == G_RENDERER.queue_family_compute_index {
			src_cmd_buffer = frame_compute_cmd_buffer_get()
		}

		// Run the copy
		buffer_copy := vk.BufferCopy {
			srcOffset = vk.DeviceSize(p_src_buffer_offset),
			dstOffset = vk.DeviceSize(p_dst_buffer_offset),
			size      = vk.DeviceSize(p_size_in_bytes),
		}

		vk.CmdCopyBuffer(
			transfer_cmd_buff,
			backend_src_buff.vk_buffer,
			backend_dst_buffer.vk_buffer,
			1,
			&buffer_copy,
		)

		// Add an entry into the transfer array
		if p_is_last_upload {
			finished_transfer_info := FinishedTransferInfo {
				dst_buffer_ref                  = p_dst_buffer_ref,
				size                            = p_total_size,
				offset                          = p_base_offset,
				post_transfer_stage             = p_post_transfer_stage,
				post_transfer_queue_family_idx  = src_queue,
				async_upload_callback_user_data = p_transfer_finished_user_data,
				async_upload_finished_callback  = p_transfer_finished_callback,
				fence_idx                       = u8(get_frame_idx()),
			}

			append(&INTERNAL.finished_transfer_infos, finished_transfer_info)
		}
	}

	//---------------------------------------------------------------------------//

	backend_begin_sliced_upload_for_buffer :: proc(
		p_buffer_ref: BufferRef,
		p_size_in_bytes: u32,
		p_offset: u32,
	) {

		backend_dst_buffer := &g_resources.backend_buffers[buffer_get_idx(p_buffer_ref)]

		// Non-dedicated transfer queue path
		if (.DedicatedTransferQueue in G_RENDERER.gpu_device_flags) == false {

			cmd_buff_ref := get_frame_cmd_buffer_ref()
			backend_cmd_buff := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buff_ref)]

			// Issue pre-copy barrier
			pre_upload_barrier := vk.BufferMemoryBarrier {
				sType = .BUFFER_MEMORY_BARRIER,
				pNext = nil,
				size = vk.DeviceSize(p_size_in_bytes),
				offset = vk.DeviceSize(p_offset),
				buffer = backend_dst_buffer.vk_buffer,
				dstAccessMask = {.TRANSFER_WRITE},
				srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
				dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			}

			vk.CmdPipelineBarrier(
				backend_cmd_buff.vk_cmd_buff,
				{.TOP_OF_PIPE},
				{.TRANSFER},
				nil,
				0,
				nil,
				1,
				&pre_upload_barrier,
				0,
				nil,
			)

			return
		}


		transfer_cmd_buff := frame_transfer_cmd_buffer_post_graphics_get()

		src_queue := backend_dst_buffer.owning_queue_family_idx

		src_cmd_buffer_ref := get_frame_cmd_buffer_ref()
		src_cmd_buffer :=
			g_resources.backend_cmd_buffers[command_buffer_get_idx(src_cmd_buffer_ref)].vk_cmd_buff

		if src_queue == G_RENDERER.queue_family_compute_index {
			src_cmd_buffer = frame_compute_cmd_buffer_get()
		}

		// Issue release and acquire buffer range 
		release_acquire_barrier := vk.BufferMemoryBarrier {
			sType = .BUFFER_MEMORY_BARRIER,
			pNext = nil,
			size = vk.DeviceSize(p_size_in_bytes),
			offset = vk.DeviceSize(p_offset),
			buffer = backend_dst_buffer.vk_buffer,
			dstAccessMask = {.TRANSFER_WRITE},
			srcQueueFamilyIndex = src_queue,
			dstQueueFamilyIndex = G_RENDERER.queue_family_transfer_index,
		}

		// Release
		vk.CmdPipelineBarrier(
			src_cmd_buffer,
			{.BOTTOM_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			1,
			&release_acquire_barrier,
			0,
			nil,
		)

		// Acquire
		vk.CmdPipelineBarrier(
			transfer_cmd_buff,
			{.BOTTOM_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			1,
			&release_acquire_barrier,
			0,
			nil,
		)

	}
}
