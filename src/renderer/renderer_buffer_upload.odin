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

	// Create the staging buffer used as upload src
	{
		buffer_desc := BufferDesc {
			// make the buffer n-times large, so we can upload data from the CPU while the GPU is still doing the transfer
			size = p_options.staging_buffer_size * p_options.num_staging_regions,
			flags = {.HostWrite, .Mapped},
			usage = {.TransferSrc},
		}

		INTERNAL.single_staging_region_size = p_options.staging_buffer_size

		INTERNAL.staging_buffer_ref = create_buffer(
			common.create_name("UploadStagingBuffer"),
			buffer_desc,
		)

		if INTERNAL.staging_buffer_ref == InvalidBufferRef {
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

@(private)
request_buffer_upload :: proc(p_request: BufferUploadRequest) -> BufferUploadResponse {
	staging_buffer := get_buffer(INTERNAL.staging_buffer_ref)

	// Check if this request will stil fit in the staging buffer 
	// or do we have to delay it to the next frame
	{
		will_request_fit := INTERNAL.staging_buffer_offset + p_request.size <= INTERNAL.single_staging_region_size

		if !will_request_fit {
			return BufferUploadResponse{ptr = nil}
		}
	}

	upload_ptr := mem.ptr_offset(staging_buffer.mapped_ptr, INTERNAL.staging_buffer_offset)

	pending_request := PendingBufferUploadRequest {
		request               = p_request,
		staging_buffer_offset = INTERNAL.single_staging_region_size * get_frame_idx() + INTERNAL.staging_buffer_offset,
	}

	append(&INTERNAL.pending_requests, pending_request)
	INTERNAL.staging_buffer_offset += p_request.size

	return BufferUploadResponse{ptr = upload_ptr}
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
