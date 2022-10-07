package renderer

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	BackendDrawCommandResource :: struct {}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_draw_command :: proc(
		p_draw_command: ^DrawCommandResource,
	) -> bool {
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_draw_command :: proc(p_draw_cmd: ^DrawCommandResource) {

	}

	//---------------------------------------------------------------------------//

}
