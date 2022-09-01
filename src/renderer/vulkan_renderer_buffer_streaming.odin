package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	// import "core:log"
	// import "core:mem"

	// import "../common"

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_buffer_streaming :: proc() -> bool {
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_run_streaming_requests :: proc(
		p_staging_buffer_ref: BufferRef,
		p_streaming_requests: [dynamic]PendingStreamingRequest,
	) {
        // @TODO Make sure that the buffer is no longer used for transfer with a fence
    }
	//---------------------------------------------------------------------------//
}
