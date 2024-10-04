package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:log"
import "core:mem"

//---------------------------------------------------------------------------//

BufferUploadRequestFlagBits :: enum u8 {
	RunOnNextFrame,
	RunSliced,
}

BufferUploadRequestFlags :: distinct bit_set[BufferUploadRequestFlagBits;u8]

//---------------------------------------------------------------------------//

@(private)
BufferUploadRequest :: struct {
	size:                            u32,
	data_ptr:                        rawptr,
	dst_buff_offset:                 u32,
	dst_buff:                        BufferRef,
	// queue on which the buffer will be used
	dst_queue_usage:                 DeviceQueueType,
	first_usage_stage:               PipelineStageFlagBits,
	flags:                           BufferUploadRequestFlags,
	async_upload_callback_user_data: rawptr,
	async_upload_finished_callback:  proc(p_user_data: rawptr),
}


//---------------------------------------------------------------------------//

@(private)
PendingBufferUploadRequest :: struct {
	using request:         BufferUploadRequest,
	staging_buffer_offset: u32,
}
//---------------------------------------------------------------------------//

BufferUploadResponseStatus :: enum {
	// Returned when the data has been uploaded into the staging buffer for non-async requests 
	// or when the data has been uploaded into the GPU itself on integrated systems
	Uploaded,
	// Returned for successfully started async requests
	Started,
	// Returned when the request couldn't be satisfied
	Failed,
}

//---------------------------------------------------------------------------//


@(private)
BufferUploadResponse :: struct {
	status: BufferUploadResponseStatus,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	// used for upload request each frame
	staging_buffer_offset:            u32,
	staging_buffer_ref:               BufferRef,
	async_staging_buffer_ref:         BufferRef,
	async_staging_buffer_offset:      u32,
	single_staging_region_size:       u32,
	single_async_staging_region_size: u32,
	last_frame_requests_per_buffer:   map[BufferRef][dynamic]BufferUploadRequest,
	async_uploads:                    [dynamic]AsyncUploadInfo,
}

//---------------------------------------------------------------------------//

BufferUploadInitOptions :: struct {
	staging_buffer_size:       u32,
	staging_async_buffer_size: u32,
	num_staging_regions:       u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
AsyncUploadInfo :: struct {
	data:                      rawptr,
	current_size_in_bytes:     u32,
	dst_buffer_ref:            BufferRef,
	current_dst_buffer_offset: u32,
	upload_callback_user_data: rawptr,
	upload_finished_callback:  proc(p_user_data: rawptr),
	post_upload_stage:         PipelineStageFlagBits,
	total_size_in_bytes:       u32,
	base_offset:               u32,
	is_initial_part:           bool,
}

//---------------------------------------------------------------------------//


@(private)
init_buffer_upload :: proc(p_options: BufferUploadInitOptions) -> bool {

	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		// On integrated GPUs we can leverage the fact, the we're sharing memory
		// and can upload directly into the buffer by mapping it persistently.
		// The mapping happens automatically in {platform}_renderer_resource_buffer.odin
		// It's the user's resposbility to make sure that used parts of the buffer are not uploaded to.
		return true
	}

	INTERNAL.last_frame_requests_per_buffer = make_map(
		map[BufferRef][dynamic]BufferUploadRequest,
		32,
		get_frame_allocator(),
	)

	// Create the staging buffer used as upload src
	{
		INTERNAL.single_staging_region_size = p_options.staging_buffer_size
		INTERNAL.single_async_staging_region_size = p_options.staging_async_buffer_size

		INTERNAL.staging_buffer_ref = allocate_buffer_ref(
			common.create_name("UploadStagingBuffer"),
		)
		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer_ref)]
		// make the buffer n-times large, so we can upload data from the CPU while the GPU is still doing the transfer
		staging_buffer.desc.size =
			p_options.staging_buffer_size * p_options.num_staging_regions * 10
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}

		if !create_buffer(INTERNAL.staging_buffer_ref) {
			log.error("Failed to create the staging buffer for upload")
			return false
		}
	}

	// Create an async staging buffer upload for sliced uploads
	{
		INTERNAL.async_uploads = make([dynamic]AsyncUploadInfo, get_frame_allocator())

		INTERNAL.async_staging_buffer_ref = allocate_buffer_ref(
			common.create_name("AsyncUploadStagingBuffer"),
		)
		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.async_staging_buffer_ref)]
		staging_buffer.desc.size =
			p_options.staging_async_buffer_size * p_options.num_staging_regions
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}

		if !create_buffer(INTERNAL.async_staging_buffer_ref) {
			log.error("Failed to create the async staging buffer for upload")
			return false
		}
	}


	return backend_init_buffer_upload(p_options)
}

//---------------------------------------------------------------------------//

@(private)
buffer_upload_begin_frame :: proc() {
	INTERNAL.staging_buffer_offset = 0
	INTERNAL.async_staging_buffer_offset = 0
}

//---------------------------------------------------------------------------//

// Used to check if a request of a given size will fit into the buffer
@(private)
dry_request_buffer_upload :: proc(p_buffer_ref: BufferRef, p_size: u32) -> bool {
	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		buffer := &g_resources.buffers[get_buffer_idx(p_buffer_ref)]
		return p_size <= buffer.desc.size
	}
	return INTERNAL.staging_buffer_offset + p_size <= INTERNAL.single_staging_region_size
}

//---------------------------------------------------------------------------//

request_buffer_upload :: proc(p_request: BufferUploadRequest) -> BufferUploadResponse {

	assert(p_request.size > 0)

	// On integrated GPUs we can just copy the data directly to the GPU memory, without any staging buffers
	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		return request_buffer_upload_integrated(p_request)
	}

	// Slice the upload accross multiple frames
	if .RunSliced in p_request.flags {
		async_upload_info := AsyncUploadInfo {
			data                      = p_request.data_ptr,
			current_size_in_bytes     = p_request.size,
			dst_buffer_ref            = p_request.dst_buff,
			current_dst_buffer_offset = p_request.dst_buff_offset,
			upload_callback_user_data = p_request.async_upload_callback_user_data,
			upload_finished_callback  = p_request.async_upload_finished_callback,
			post_upload_stage         = p_request.first_usage_stage,
			total_size_in_bytes       = p_request.size,
			base_offset               = p_request.dst_buff_offset,
			is_initial_part           = true,
		}

		append(&INTERNAL.async_uploads, async_upload_info)

		return BufferUploadResponse{status = .Started}
	}

	// When this request has to run synchronously,  make sure we have 
	// enough space in the staging buffer to run it at once
	if dry_request_buffer_upload(p_request.dst_buff, p_request.size) == false {
		return BufferUploadResponse{status = .Failed}
	}

	if .RunOnNextFrame in p_request.flags {

		// Create a new entry if there were no upload requests for this buffer yet
		if (p_request.dst_buff in INTERNAL.last_frame_requests_per_buffer) == false {
			INTERNAL.last_frame_requests_per_buffer[p_request.dst_buff] = make(
				[dynamic]BufferUploadRequest,
				get_frame_allocator(),
			)
		}
		append(&INTERNAL.last_frame_requests_per_buffer[p_request.dst_buff], p_request)

		return BufferUploadResponse{status = .Uploaded}
	}

	pending_request := buffer_upload_send_data(p_request)
	requests := common.into_dynamic([]PendingBufferUploadRequest{pending_request})

	backend_run_buffer_upload_requests(INTERNAL.staging_buffer_ref, p_request.dst_buff, requests)

	return BufferUploadResponse{status = .Uploaded}
}
//---------------------------------------------------------------------------//

@(private)
run_last_frame_buffer_upload_requests :: proc() {

	last_frame_requests_per_buffer := make_map(
		map[BufferRef][dynamic]BufferUploadRequest,
		len(INTERNAL.last_frame_requests_per_buffer),
		get_next_frame_allocator(),
	)

	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	for buffer_ref, pending_requests in INTERNAL.last_frame_requests_per_buffer {

		common.arena_reset(temp_arena)

		not_satisfied_requests := make([dynamic]BufferUploadRequest, get_next_frame_allocator())
		requests_to_run := make([dynamic]PendingBufferUploadRequest, temp_arena.allocator)

		for request in pending_requests {

			// Delay the request to the next frame if the staging buffer is full
			if dry_request_buffer_upload(buffer_ref, request.size) == false {
				append(&not_satisfied_requests, request)
				continue
			}

			append(&requests_to_run, buffer_upload_send_data(request))
		}

		backend_run_buffer_upload_requests(
			INTERNAL.staging_buffer_ref,
			buffer_ref,
			requests_to_run,
		)

		if len(not_satisfied_requests) == 0 {
			delete(not_satisfied_requests)
			continue
		}

		last_frame_requests_per_buffer[buffer_ref] = not_satisfied_requests
	}

	INTERNAL.last_frame_requests_per_buffer = last_frame_requests_per_buffer
}

//---------------------------------------------------------------------------//

@(private = "file")
buffer_upload_send_data :: proc(p_request: BufferUploadRequest) -> PendingBufferUploadRequest {

	staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer_ref)]

	pending_request := PendingBufferUploadRequest {
		request               = p_request,
		staging_buffer_offset = INTERNAL.single_staging_region_size *
			get_frame_idx() + INTERNAL.staging_buffer_offset,
	}

	upload_ptr := mem.ptr_offset(staging_buffer.mapped_ptr, pending_request.staging_buffer_offset)
	mem.copy(upload_ptr, p_request.data_ptr, int(p_request.size))

	INTERNAL.staging_buffer_offset += p_request.size

	return pending_request
}

//---------------------------------------------------------------------------//

@(private = "file")
request_buffer_upload_integrated :: proc(p_request: BufferUploadRequest) -> BufferUploadResponse {
	buffer := &g_resources.buffers[get_buffer_idx(p_request.dst_buff)]
	dst_ptr := mem.ptr_offset(buffer.mapped_ptr, p_request.dst_buff_offset)
	mem.copy(dst_ptr, p_request.data_ptr, int(p_request.size))
	if p_request.async_upload_finished_callback != nil {
		p_request.async_upload_finished_callback(p_request.async_upload_callback_user_data)
	}
	return BufferUploadResponse{status = .Uploaded}
}


//---------------------------------------------------------------------------//

@(private)
buffer_upload_process_async_requests :: proc() {

	async_uploads := make([dynamic]AsyncUploadInfo, get_next_frame_allocator())

	if len(INTERNAL.async_uploads) == 0 {
		INTERNAL.async_uploads = async_uploads
		return
	}

	backend_upload_sliced_proc := backend_buffer_upload_run_sliced_sync
	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_upload_sliced_proc = backend_buffer_upload_run_sliced_async
	}

	staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.async_staging_buffer_ref)]

	for &async_upload_info in INTERNAL.async_uploads {

		if async_upload_info.current_dst_buffer_offset ==
		   INTERNAL.single_async_staging_region_size {
			append(&async_uploads, async_upload_info)
			continue
		}


		// Check if this is the initial upload info
		if async_upload_info.is_initial_part {
			backend_begin_sliced_upload_for_buffer(
				async_upload_info.dst_buffer_ref,
				async_upload_info.total_size_in_bytes,
				async_upload_info.current_dst_buffer_offset,
			)
		}
		async_upload_info.is_initial_part = false

		upload_size := async_upload_info.current_size_in_bytes

		// Half the request size until it fits
		for INTERNAL.async_staging_buffer_offset + upload_size >
		    INTERNAL.single_async_staging_region_size {
			upload_size /= 2
		}

		if upload_size == 0 {
			append(&async_uploads, async_upload_info)
			continue
		}

		async_upload_info.current_size_in_bytes -= upload_size

		// Upload the data into staging buffer
		staging_buffer_offset :=
			INTERNAL.single_async_staging_region_size * get_frame_idx() +
			INTERNAL.async_staging_buffer_offset
		staging_buffer_ptr := mem.ptr_offset(staging_buffer.mapped_ptr, staging_buffer_offset)

		INTERNAL.async_staging_buffer_offset += upload_size
		mem.copy(staging_buffer_ptr, async_upload_info.data, int(upload_size))

		// Run async buffer upload
		backend_upload_sliced_proc(
			async_upload_info.dst_buffer_ref,
			async_upload_info.current_dst_buffer_offset,
			INTERNAL.async_staging_buffer_ref,
			staging_buffer_offset,
			upload_size,
			async_upload_info.post_upload_stage,
			async_upload_info.upload_finished_callback,
			async_upload_info.upload_callback_user_data,
			async_upload_info.current_size_in_bytes == 0,
			async_upload_info.total_size_in_bytes,
			async_upload_info.base_offset,
		)

		// Advance the upload
		async_upload_info.current_dst_buffer_offset += upload_size
		async_upload_info.data = mem.ptr_offset((^byte)(async_upload_info.data), int(upload_size))

		// If the upload is still going, add it to the async uploads
		if async_upload_info.current_size_in_bytes > 0 {
			append(&async_uploads, async_upload_info)
		}
	}

	INTERNAL.async_uploads = async_uploads
}

//---------------------------------------------------------------------------//

@(private)
buffer_upload_submit_pre_graphics :: proc() {
	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_buffer_upload_submit_pre_graphics()
	}
}

//---------------------------------------------------------------------------//

@(private)
buffer_upload_submit_post_graphics :: proc() {
	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_buffer_upload_submit_post_graphics()
	}
}

//---------------------------------------------------------------------------//

@(private)
buffer_upload_finalize_finished_uploads :: proc() {
	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_buffer_upload_finalize_finished_uploads()
	}
}

//---------------------------------------------------------------------------//
