package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	BackendRenderPassResource :: struct {
	}

	@(private)
	backend_init_render_passes :: proc() {
	}

	//---------------------------------------------------------------------------//

	backend_create_render_pass :: proc(
		p_render_pass_desc: RenderPassDesc,
		p_render_pass: ^RenderPassResource,
	) -> bool {
		// TODO
		return true
	}

	//---------------------------------------------------------------------------//	
}
