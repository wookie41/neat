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

ShaderRef :: Ref(ShaderResource)

//---------------------------------------------------------------------------//

InvalidShaderRef := ShaderRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private="file")
G_SHADER_REF_ARRAY: RefArray(ShaderResource)

//---------------------------------------------------------------------------//

@(private)
load_shaders :: proc() -> bool {

	G_SHADER_REF_ARRAY = create_ref_array(ShaderResource, MAX_SHADERS)

	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	shaders_config := "app_data/renderer/config/shaders.json"
	shaders_json_data, file_read_ok := os.read_entire_file(shaders_config)

	if file_read_ok == false {
		log.error("Failed to open the shaders config file")
		return false
	}

	shader_json_entries: []ShaderJSONEntry

	// Make sure that the bin and reflect dirs exist
	{
		dirs := []string{
			"app_data/renderer/assets/shaders/bin",
			"app_data/renderer/assets/shaders/reflect",
		}

		for dir in dirs {
			if os.exists(dir) == false {
				os.make_directory(dir, 0)
			}
		}
	}

	// Parse the file
	{
		if err := json.unmarshal(shaders_json_data, &shader_json_entries); err != nil {
			log.errorf("Failed to unmarshal shaders json: %s\n", err)
			delete(shaders_json_data)
			return false
		}
	}

	// Load the shaders
	for entry in shader_json_entries {

		name := common.create_name(entry.name)
		ref := ShaderRef(create_ref(ShaderResource, &G_SHADER_REF_ARRAY, name))
		shader_resource, ok := backend_compile_shader(entry, ref)
		if ok == false {
			continue
		}

		G_SHADER_REF_ARRAY.resource_array[get_ref_idx(ref)] = shader_resource
	}

	return true
}
//---------------------------------------------------------------------------//

get_shader :: proc(p_ref: ShaderRef) -> ^ShaderResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_SHADER_REF_ARRAY.resource_array)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_SHADER_REF_ARRAY.generations[idx])

	return &G_SHADER_REF_ARRAY.resource_array[idx]
}

//---------------------------------------------------------------------------//

@(private)
find_shader_by_name :: proc(p_name: common.Name) -> ShaderRef {
	ref := find_ref_by_name(ShaderResource, &G_SHADER_REF_ARRAY, p_name)
	if ref == InvalidShaderRef {
		return InvalidShaderRef
	}
	return ShaderRef(ref)
}

//---------------------------------------------------------------------------//
