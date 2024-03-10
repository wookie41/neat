package renderer
//---------------------------------------------------------------------------//

import "core:c/libc"
import "core:log"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

import "../common"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

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
	backend_create_shader :: proc(p_ref: ShaderRef) -> (create_result: bool) {

		shader_idx := get_shader_idx(p_ref)
		shader := &g_resources.shaders[shader_idx]
		backend_shader := &g_resources.backend_shaders[shader_idx]

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		// Determine compile target
		compile_target: string
		switch shader.desc.stage {
		case .Vertex:
			compile_target = "vs_6_7"
		case .Fragment:
			compile_target = "ps_6_7"
		case .Compute:
			compile_target = "cs_6_7"
		}

		shader_path := common.get_string(shader.desc.file_path)
		shader_src_path := common.aprintf(
			temp_arena.allocator,
			"app_data/renderer/assets/shaders/%s",
			shader_path,
		)
		shader_bin_path := common.aprintf(
			temp_arena.allocator,
			"app_data/renderer/assets/shaders/bin/%s.sprv",
			shader_path,
		)

		// Compile the shader
		{
			// Add defines for macros
			shader_defines := ""
			shader_defines_log := ""
			for feature in shader.desc.features {
				shader_defines = common.aprintf(
					temp_arena.allocator,
					"%s -D %s",
					shader_defines,
					feature,
				)
				shader_defines_log = common.aprintf(
					temp_arena.allocator,
					"%s\n%s\n",
					shader_defines_log,
					feature,
				)
			}

			log.infof("Compiling shader %s with features %s\n", shader_path, shader_defines_log)

			// @TODO replace with a single command when 
			// https://github.com/microsoft/DirectXShaderCompiler/issues/4496 is fixed
			compile_cmd := common.aprintf(
				temp_arena.allocator,
				"dxc -spirv -fspv-target-env=vulkan1.3 -HV 2021 -T %s -Fo %s %s %s",
				compile_target,
				shader_bin_path,
				shader_src_path,
				shader_defines,
			)

			if res := libc.system(strings.clone_to_cstring(compile_cmd, temp_arena.allocator));
			   res != 0 {
				log.warnf("Failed to compile shader %s: error code %d", shader_path, res)
				return false
			}
		}

		// Create the shader module
		{
			shader_code, ok := os.read_entire_file(shader_bin_path, temp_arena.allocator)
			if ok == false {
				log.warnf("Failed to read shader code for shader %s", shader_path)
				return false
			}
			module_create_info := vk.ShaderModuleCreateInfo {
				sType    = .SHADER_MODULE_CREATE_INFO,
				codeSize = len(shader_code),
				pCode    = cast(^u32)raw_data(shader_code),
			}
			if create_res := vk.CreateShaderModule(
				G_RENDERER.device,
				&module_create_info,
				nil,
				&backend_shader.vk_module,
			); create_res != .SUCCESS {
				log.warnf("Failed to create module for shader %s: %s", shader_path, create_res)
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

	backend_reload_shader :: proc(p_shader_ref: ShaderRef) -> bool {
		shader := &g_resources.backend_shaders[get_shader_idx(p_shader_ref)]
		old_vk_module := shader.vk_module
		if backend_create_shader(p_shader_ref) == true {
			vk.DestroyShaderModule(G_RENDERER.device, old_vk_module, nil)
			return true
		}
		return false
	}

}
