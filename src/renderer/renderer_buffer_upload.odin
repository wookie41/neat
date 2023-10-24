package renderer

//---------------------------------------------------------------------------//

import "core:log"
import "core:mem"

import "../common"

/*
	Upload works by getting a pointer into the staging buffer at which 
	the data should be uploaded by the user by calling request_buffer_upload(), 
	Later, at the end of the current frame, all of the data in the 
	staging buffer will be transfered to the appropriate buffers, specified 
	by the dst_buff in the UploadRequest Ref and appropriate barriers
	will be placed for synchronization.
	If the request can't be satisfied in the current frame, request_buffer_upload()
	will return a nullptr.
 */

//---------------------------------------------------------------------------//


@(private)
BufferUploadRequest :: struct {
	size:              u32,
	dst_buff_offset:   u32,
	dst_buff:          BufferRef,
	// @TODO add support so that we can specify multiple queues
	dst_queue_usage:   DeviceQueueType, // queue on which the buffer will be used
	first_usage_stage: PipelineStageFlagBits,
}

//---------------------------------------------------------------------------//

@(private)
PendingBufferUploadRequest :: struct {
	using request:         BufferUploadRequest,
	staging_buffer_offset: u32,
}
//---------------------------------------------------------------------------//

@(private)
BufferUploadResponse :: struct {
	ptr: rawptr,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	// used for upload request each frame
	staging_buffer_offset:      u32,
	staging_buffer_ref:         BufferRef,
	single_staging_region_size: u32,
	pending_requests:           [dynamic]PendingBufferUploadRequest,
}

//---------------------------------------------------------------------------//

BufferUploadInitOptions :: struct {
	staging_buffer_size: u32,
	num_staging_regions: u32,
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

	// Create the staging buffer used as upload src
	{
		INTERNAL.single_staging_region_size = p_options.staging_buffer_size

		INTERNAL.staging_buffer_ref = allocate_buffer_ref(
			common.create_name("UploadStagingBuffer"),
		)
		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer_ref)]
		// make the buffer n-times large, so we can upload data from the CPU while the GPU is still doing the transfer
		staging_buffer.desc.size =
			p_options.staging_buffer_size * p_options.num_staging_regions
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}

		if !create_buffer(INTERNAL.staging_buffer_ref) {
			log.error("Failed to create the staging buffer for upload")
			return false
		}
	}

	INTERNAL.pending_requests = make(
		[dynamic]PendingBufferUploadRequest,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	INTERNAL.staging_buffer_offset = 0

	return backend_init_buffer_upload(p_options)
}

//---------------------------------------------------------------------------//

@(private)
buffer_upload_begin_frame :: proc() {
	backend_buffer_upload_begin_frame()
}

//---------------------------------------------------------------------------//

// Used to check if a request of a given size will fit into the buffer
@(private)
dry_request_buffer_upload :: proc(p_buffer_ref: BufferRef, p_size: u32) -> bool {
	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		buffer := &g_resources.buffers[get_buffer_idx(p_buffer_ref)]
		return p_size <= buffer.desc.size 
	}
	return(
		INTERNAL.staging_buffer_offset + p_size <=
		INTERNAL.single_staging_region_size
	)
}

//---------------------------------------------------------------------------//

@(private)
request_buffer_upload :: proc(p_request: BufferUploadRequest) -> BufferUploadResponse {
	if dry_request_buffer_upload(p_request.dst_buff, p_request.size) == false {
		return BufferUploadResponse{ptr = nil}
	}

	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		return request_buffer_upload_integrated(p_request)
	}
	return request_buffer_upload_dicrete(p_request)
}
//---------------------------------------------------------------------------//

@(private)
run_buffer_upload_requests :: #force_inline proc() {
	backend_run_buffer_upload_requests(
		INTERNAL.staging_buffer_ref,
		INTERNAL.pending_requests,
	)
	clear(&INTERNAL.pending_requests)
	INTERNAL.staging_buffer_offset = 0
}

//---------------------------------------------------------------------------//

@(private="file")
request_buffer_upload_dicrete :: proc(p_request :BufferUploadRequest) -> BufferUploadResponse {
	staging_buffer := &g_resources.buffers[ get_buffer_idx(INTERNAL.staging_buffer_ref)]

	// Check if this request will stil fit in the staging buffer 
	// or do we have to delay it to the next frame

	upload_ptr := mem.ptr_offset(
		staging_buffer.mapped_ptr,
		INTERNAL.staging_buffer_offset,
	)

	pending_request := PendingBufferUploadRequest {
		request               = p_request,
		staging_buffer_offset = INTERNAL.single_staging_region_size *
			get_frame_idx() + INTERNAL.staging_buffer_offset,
	}

	append(&INTERNAL.pending_requests, pending_request)
	INTERNAL.staging_buffer_offset += p_request.size

	return BufferUploadResponse{ptr = upload_ptr}
}

//---------------------------------------------------------------------------//

@(private="file")
request_buffer_upload_integrated :: proc(p_request : BufferUploadRequest) -> BufferUploadResponse {
	buffer := &g_resources.buffers[ get_buffer_idx(p_request.dst_buff)]
	return BufferUploadResponse{ptr = mem.ptr_offset(buffer.mapped_ptr, p_request.dst_buff_offset)}
}