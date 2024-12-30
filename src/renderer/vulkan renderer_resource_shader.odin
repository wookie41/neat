package renderer
//---------------------------------------------------------------------------//

import "core:c/libc"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

import "../common"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	BACKEND_COMPILED_SHADERS_FOLDER :: "sprv"
	BACKEND_COMPILED_SHADERS_EXTENSION :: "sprv"

	//---------------------------------------------------------------------------//

	@(private)
	BackendShaderResource :: struct {
		vk_module: vk.ShaderModule,
	}

	//---------------------------------------------------------------------------//


	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_shaders :: proc() -> bool {
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_deinit_shaders :: proc() {
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_shader :: proc(
		p_ref: ShaderRef,
		p_shader_code: []byte,
	) -> (
		create_result: bool,
	) {

		shader_idx := get_shader_idx(p_ref)
		shader := &g_resources.shaders[shader_idx]
		backend_shader := &g_resources.backend_shaders[shader_idx]

		// Create the shader module
		{
			module_create_info := vk.ShaderModuleCreateInfo {
				sType    = .SHADER_MODULE_CREATE_INFO,
				codeSize = len(p_shader_code),
				pCode    = cast(^u32)raw_data(p_shader_code),
			}
			if create_res := vk.CreateShaderModule(
				G_RENDERER.device,
				&module_create_info,
				nil,
				&backend_shader.vk_module,
			); create_res != .SUCCESS {
				log.warnf("Failed to create module for shader %s: %s\n", common.get_string(shader.desc.name), create_res)
				return false
			}
		}

		return true
	}
	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_shader :: proc(p_shader_ref: ShaderRef) {
		shader := &g_resources.backend_shaders[get_shader_idx(p_shader_ref)]
		vk.DestroyShaderModule(G_RENDERER.device, shader.vk_module, nil)
	}

	//---------------------------------------------------------------------------//

	backend_reload_shader :: proc(p_shader_ref: ShaderRef, p_shader_code: []byte) -> bool {
		shader := &g_resources.backend_shaders[get_shader_idx(p_shader_ref)]
		old_vk_module := shader.vk_module
		if backend_create_shader(p_shader_ref, p_shader_code) == true {
			vk.DestroyShaderModule(G_RENDERER.device, old_vk_module, nil)
			return true
		}
		return false
	}


	//---------------------------------------------------------------------------//

	@(private)
	backend_compile_shader :: proc(
		p_src_path: string,
		p_bin_path: string,
		p_shader_stage: ShaderStage,
		p_shader_defines: string,
	) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		// Determine compile target and entry point
		compile_target: string
		entry_point: string
		switch p_shader_stage {
		case .Vertex:
			compile_target = "vs_6_7"
			entry_point = "VSMain"
		case .Pixel:
			compile_target = "ps_6_7"
			entry_point = "PSMain"
		case .Compute:
			compile_target = "cs_6_7"
			entry_point = "CSMain"
		case:
			assert(false, "Unsupported shader type")
		}

		// @TODO strip debug info
		compile_cmd := common.aprintf(
			temp_arena.allocator,
			"dxc -spirv -fspv-target-env=vulkan1.3 -HV 2021 -T %s -Fo %s %s %s -E %s",
			compile_target,
			p_bin_path,
			p_src_path,
			p_shader_defines,
			entry_point,
		)

		if res := libc.system(strings.clone_to_cstring(compile_cmd, temp_arena.allocator));
		   res != 0 {
			log.warnf("Failed to compile shader %s: error code %d", p_src_path, res)
			return false
		}

		return true
	}

}
