
package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	// import vk "vendor:vulkan"

	//---------------------------------------------------------------------------//

	@(private)
	BackendRenderTaskResource :: struct {
	}

	//---------------------------------------------------------------------------//


	@(private="file")
	INTERNAL: struct {
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_render_tasks :: proc() -> bool {
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_deinit_render_tasks :: proc() {
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_render_task :: proc(
		p_ref: RenderTaskRef,
		p_render_task: ^RenderTaskResource,
		p_render_task_config: RenderTaskConfig,
	) -> bool {
		return true
	}
	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_render_task :: proc(p_render_task: ^RenderTaskResource) {
	}

}
