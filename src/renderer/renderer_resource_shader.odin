
package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:os"
import "core:log"
import "core:encoding/json"
import "core:strings"
import "core:hash"
import "core:slice"

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	shader_by_hash: map[u32]ShaderRef,
}

//---------------------------------------------------------------------------//

@(private)
ShaderJSONEntry :: struct {
	name:     string,
	path:     string,
	features: []string,
}

//---------------------------------------------------------------------------//

ShaderDesc :: struct {
	name:      common.Name,
	file_path: string,
	type:      ShaderType,
	features:  []string,
}


//---------------------------------------------------------------------------//

@(private)
ShaderType :: enum u8 {
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

//---------------------------------------------------------------------------//

ShaderResource :: struct {
	using backend_shader: BackendShaderResource,
	desc:                 ShaderDesc,
}

//---------------------------------------------------------------------------//

ShaderRef :: Ref(ShaderResource)

//---------------------------------------------------------------------------//

InvalidShaderRef := ShaderRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_SHADER_REF_ARRAY: RefArray(ShaderResource)

//---------------------------------------------------------------------------//

init_shaders :: proc() -> bool {
	G_SHADER_REF_ARRAY = create_ref_array(ShaderResource, MAX_SHADERS)

	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator

	// Load base shader permutations
	shaders_config := "app_data/renderer/config/shaders.json"
	shaders_json_data, file_read_ok := os.read_entire_file(shaders_config)
	defer free(raw_data(shaders_json_data))

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

	// Parse the shader config file
	if err := json.unmarshal(shaders_json_data, &shader_json_entries); err != nil {
		log.errorf("Failed to unmarshal shaders json: %s\n", err)
		delete(shaders_json_data)
		return false
	}

	// Load the shaders
	for entry in shader_json_entries {

		name := common.create_name(entry.name)
		shader_ref := allocate_shader_ref(name)
		shader := get_shader(shader_ref)
		shader.desc.file_path = entry.path
		shader.desc.features = slice.clone(
			entry.features,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		if strings.has_suffix(entry.name, ".vert") {
			shader.desc.type = .VERTEX
		} else if strings.has_suffix(entry.name, ".frag") {
			shader.desc.type = .FRAGMENT
		} else if strings.has_suffix(entry.name, ".comp") {
			shader.desc.type = .COMPUTE
		} else {
			log.warnf("Unknown shader type %s...", entry.name)
			free_ref(ShaderResource, &G_SHADER_REF_ARRAY, shader_ref)
			return false
		}

		if create_shader(shader_ref) == false {
			free_ref(ShaderResource, &G_SHADER_REF_ARRAY, shader_ref)
			continue
		}
	}

	return backend_init_shaders()
}

//---------------------------------------------------------------------------//

deinit_shaders :: proc() {
	backend_deinit_shaders()
}

//---------------------------------------------------------------------------//

create_shader :: proc(p_shader_ref: ShaderRef) -> bool {
	shader := get_shader(p_shader_ref)
	shader_hash := calculate_hash_for_shader(&shader.desc)
	assert((shader_hash in INTERNAL.shader_by_hash) == false)
	if backend_create_shader(p_shader_ref, shader) == false {
		destroy_shader(p_shader_ref)
		return false
	}
	INTERNAL.shader_by_hash[shader_hash] = p_shader_ref
	return true
}

//---------------------------------------------------------------------------//

allocate_shader_ref :: proc(p_name: common.Name) -> ShaderRef {
	ref := ShaderRef(create_ref(ShaderResource, &G_SHADER_REF_ARRAY, p_name))
	get_shader(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_shader :: proc(p_ref: ShaderRef) -> ^ShaderResource {
	return get_resource(ShaderResource, &G_SHADER_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_shader :: proc(p_ref: ShaderRef) {
	shader := get_shader(p_ref)
	backend_destroy_shader(shader)
	delete(shader.desc.features, G_RENDERER_ALLOCATORS.resource_allocator)
	free_ref(ShaderResource, &G_SHADER_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

find_shader_by_name :: proc(p_name: common.Name) -> ShaderRef {
	ref := find_ref_by_name(ShaderResource, &G_SHADER_REF_ARRAY, p_name)
	if ref == InvalidShaderRef {
		return InvalidShaderRef
	}
	return ShaderRef(ref)
}

//--------------------------------------------------------------------------//

// Creates a new shader permutation using the base shader
create_shader_permutation_with :: proc(
	p_name: common.Name,
	p_base_shader_ref: ShaderRef,
	p_features: []string,
	p_merge_features: bool,
) -> ShaderRef {
	base_shader := get_shader(p_base_shader_ref)

	permutation_desc := base_shader.desc

	if p_merge_features {
		num_features := len(p_features) + len(base_shader.desc.features)
		permutation_desc.features = make(
			[]string,
			num_features,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for feature, i in base_shader.desc.features {
			permutation_desc.features[i] = feature
		}

		for feature, i in p_features {
			permutation_desc.features[i + len(base_shader.desc.features)] = feature
		}

	} else {

		num_features := len(p_features)
		permutation_desc.features = make(
			[]string,
			num_features,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for feature, i in p_features {
			permutation_desc.features[i] = feature
		}

	}

	permutation_hash := calculate_hash_for_shader(&permutation_desc)
	if permutation_hash in INTERNAL.shader_by_hash {
		return INTERNAL.shader_by_hash[permutation_hash]
	}

	permutation_ref := allocate_shader_ref(p_name)
	permutation := get_shader(permutation_ref)

	permutation.desc = permutation_desc

	if create_shader(permutation_ref) {
		return permutation_ref
	}

	return InvalidShaderRef
}

//--------------------------------------------------------------------------//

@(private = "file")
calculate_hash_for_shader :: proc(p_shader_desc: ^ShaderDesc) -> u32 {
	h := hash.crc32(transmute([]u8)p_shader_desc.file_path)
	return h ~ common.hash_string_array(p_shader_desc.features)
}

//--------------------------------------------------------------------------//
