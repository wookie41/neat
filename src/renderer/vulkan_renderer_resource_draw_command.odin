package renderer

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	BackendDrawCommandResource :: struct {}

	//---------------------------------------------------------------------------//

	backend_create_draw_command :: proc(
		p_ref: DrawCommandRef,
		p_draw_command: ^DrawCommandResource,
	) -> bool {

	}

	//---------------------------------------------------------------------------//
}
