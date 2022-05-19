package renderer

//---------------------------------------------------------------------------//

import "core:encoding/json"
import "core:os"
import "core:log"
import "core:fmt"
import "core:strings"
import "../common"
import "core:c/libc"

//---------------------------------------------------------------------------//

@(private = "file")
ShaderJSONEntry :: struct {
	name: string,
	path: string,
}

//---------------------------------------------------------------------------//

@private
ShaderResource :: struct {
    name: common.Name,
}


@(private="file")
G_SHADER_RESOURCES : [dynamic]ShaderResource

//---------------------------------------------------------------------------//

@private
load_shaders :: proc() -> bool {

    context.allocator = G_RENDERER_ALLOCATORS.temp_arena_allocator
    defer free_all(G_RENDERER_ALLOCATORS.temp_arena_allocator)

	shaders_config := "app_data/renderer/config/shaders.json"
	shaders_json_data, file_read_ok := os.read_entire_file(shaders_config)

	if file_read_ok == false {
		log.error("Failed to open the shaders config file")
		return false
	}

	shader_json_entries: []ShaderJSONEntry

	// Parse the file
	{
		defer delete(shaders_json_data)
		if err := json.unmarshal(shaders_json_data, &shader_json_entries); err != nil {
			log.errorf("Failed to unmarshal shaders json: %s\n", err)
			delete(shaders_json_data)
			return false
		}
	}


    // Load the shaders
	for entry in shader_json_entries {

        // Check for duplicate entries
        for shader in G_SHADER_RESOURCES {
            if common.name_equal(shader.name, entry.name) {
                log.warnf("Duplicate entry for shader with name %s\n", entry.name)
                continue
            }
        }

		// Check if the shader is already compiled
		shader_bin_path := fmt.aprintf(
			"app_data/renderer/assets/shaders/bin/%s.sprv",
			entry.name,
		)

		if os.exists(shader_bin_path) {
            continue
		}

        log.infof("Compiling shader %s...\n", entry.name)

        shader_src_path := fmt.aprintf(
			"app_data/renderer/assets/shaders/%s",
			entry.name,
		)

        compile_cmd := fmt.aprintf(
			"glslc %s -o %s",
			shader_src_path, shader_bin_path,
		)

        if res := libc.system(strings.clone_to_cstring(compile_cmd)); res != 0 {
            log.warnf("Failed to compile shader %s: error code %d\n", entry.name, res)
            continue
        }
        
        shader_resource := ShaderResource {
            name = common.make_name(entry.name),
        }

        append(&G_SHADER_RESOURCES, shader_resource)
	}

	return true
}
//---------------------------------------------------------------------------//
