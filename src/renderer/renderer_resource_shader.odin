package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:os"
import "core:log"
import "core:encoding/json"

import "../common"

//---------------------------------------------------------------------------//

@(private)
ShaderJSONEntry :: struct {
	name: string,
	path: string,
}

//---------------------------------------------------------------------------//

@(private)
ShaderResource :: struct {
	ref:                    ShaderRef,
	name:                   common.Name,
	type:                   ShaderType,
	using backend_resource: BackendShaderResource,
}

//---------------------------------------------------------------------------//

@(private)
ShaderType :: enum u8 {
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

//---------------------------------------------------------------------------//


// @TODO Use a proper ref, with generation and index
ShaderRef :: u32
InvalidShaderRef :: ShaderRef(c.UINT32_MAX)

@private
G_SHADER_RESOURCES: [dynamic]ShaderResource

//---------------------------------------------------------------------------//

@(private)
find_shader_by_name :: proc(p_name: common.Name) -> ShaderRef {
	for shader in G_SHADER_RESOURCES {
		if common.name_equal(p_name, shader.name) {
			return shader.ref
		}
	}
	return InvalidShaderRef
}

//---------------------------------------------------------------------------//

@(private)
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


		next_ref := ShaderRef(len(G_SHADER_RESOURCES))
		shader_resource, ok := backend_compile_shader(entry, next_ref)
		if ok == false {
			continue
		}

		append(&G_SHADER_RESOURCES, shader_resource)
	}

	return true
}

//---------------------------------------------------------------------------//
