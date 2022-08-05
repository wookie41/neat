package renderer

//---------------------------------------------------------------------------//

import "core:log"
import "core:mem"

import "../common"

//---------------------------------------------------------------------------//

@(private)
StreamingRequest :: struct {
	size:              u32,
	dst_buff:          BufferRef,
	first_usage_stage: PipelineStageFlagBits,
}

//---------------------------------------------------------------------------//

@(private)
PendingStreamingRequest :: struct {
	using request:         StreamingRequest,
	staging_buffer_offset: u32,
}
//---------------------------------------------------------------------------//

@(private)
StreamingResponse :: struct {
	ptr: rawptr,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	// used for streaming request each frame
	staging_buffer_offset: u32,
	staging_buffer_refs:   [2]BufferRef,
	pending_requests:      [dynamic]PendingStreamingRequest,
}

//---------------------------------------------------------------------------//

@(private)
init_buffer_streaming :: proc() -> bool {

	// Create the staging buffers used as upload src
	{
		buffer_desc := BufferDesc {
			size = 64 * common.MEGABYTE,
			flags = {.HostWrite, .Mapped},
			usage = {.TransferSrc},
		}

		for i in 0 ..< 2 {
			INTERNAL.staging_buffer_refs[i] = create_buffer(
				common.create_name("StreamingStagingBuffer"),
				buffer_desc,
			)

			if INTERNAL.staging_buffer_refs[i] == InvalidBufferRef {
				log.error("Failed to create the staging buffer for streaming")
				return false
			}

		}

	}

	INTERNAL.pending_requests = make(
		[dynamic]PendingStreamingRequest,
		G_RENDERER_ALLOCATORS.frame_allocator,
	)

	return backend_init_buffer_streaming()
}

//---------------------------------------------------------------------------//

request_streaming :: proc(p_request: StreamingRequest) -> StreamingResponse {
	staging_buffer := get_buffer(INTERNAL.staging_buffer_refs[G_RENDERER.frame_id % 2])

	// Check if this request will stil fit in the staging buffer 
	// or do we have to delay it to the next frame
	{
		will_request_fit := INTERNAL.staging_buffer_offset + p_request.size <= staging_buffer.desc.size

		if !will_request_fit {
			return StreamingResponse{ptr = nil}
		}
	}

	upload_ptr := mem.ptr_offset(staging_buffer.mapped_ptr, INTERNAL.staging_buffer_offset)

	pending_request := PendingStreamingRequest {
		request               = p_request,
		staging_buffer_offset = INTERNAL.staging_buffer_offset,
	}

	append(&INTERNAL.pending_requests, pending_request)
	INTERNAL.staging_buffer_offset += p_request.size

	return StreamingResponse{ptr = upload_ptr}
}

//---------------------------------------------------------------------------//

@(private)
run_streaming_requests :: #force_inline proc() {
	backend_run_streaming_requests(
		INTERNAL.staging_buffer_refs[G_RENDERER.frame_id % 2],
		INTERNAL.pending_requests,
	)
	clear(&INTERNAL.pending_requests)
}

//---------------------------------------------------------------------------//
