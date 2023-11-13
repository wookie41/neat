
package renderer

// @TODO Figure out when we should free the shader, as they can be used by
// multiple material instances. For now we always keep them loaded

//---------------------------------------------------------------------------//

import "core:c"
import "core:encoding/json"
import "core:hash"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import "../common"

//---------------------------------------------------------------------------//

BASE_SHADERS_PATH :: "app_data/renderer/assets/shaders/"

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
	file_path: common.Name,
	stage:     ShaderStage,
	features:  []string,
}

//---------------------------------------------------------------------------//

@(private)
ShaderStage :: enum u8 {
	Vertex,
	Fragment,
	Compute,
}

ShaderStageFlags :: distinct bit_set[ShaderStage;u8]

//---------------------------------------------------------------------------//

ShaderFlagBits :: enum u16 {
	UsesBindlessArray,
}

ShaderFlags :: distinct bit_set[ShaderFlagBits;u16]

//---------------------------------------------------------------------------//

ShaderResource :: struct {
	desc:  ShaderDesc,
	flags: ShaderFlags,
	hash:  u32,
}

//---------------------------------------------------------------------------//

ShaderRef :: common.Ref(ShaderResource)

//---------------------------------------------------------------------------//

InvalidShaderRef := ShaderRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_SHADER_REF_ARRAY: common.RefArray(ShaderResource)

//---------------------------------------------------------------------------//

init_shaders :: proc() -> bool {
	G_SHADER_REF_ARRAY = common.ref_array_create(
		ShaderResource,
		MAX_SHADERS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.shaders = make_soa(
		#soa[]ShaderResource,
		MAX_SHADERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	g_resources.backend_shaders = make_soa(
		#soa[]BackendShaderResource,
		MAX_SHADERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	// Load base shader permutations
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

	// Parse the shader config file
	if err := json.unmarshal(shaders_json_data, &shader_json_entries); err != nil {
		log.errorf("Failed to unmarshal shaders json: %s\n", err)
		return false
	}

	// Load the shaders
	for entry in shader_json_entries {

		name := common.create_name(entry.name)
		shader_ref := allocate_shader_ref(name)
		shader := &g_resources.shaders[get_shader_idx(shader_ref)]
		shader.desc.file_path = common.create_name(entry.path)
		shader.desc.features = slice.clone(
			entry.features,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for feature, i in shader.desc.features {
			shader.desc.features[i] = strings.clone(
				feature,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

		}

		if strings.has_suffix(entry.name, ".vert") {
			shader.desc.stage = .Vertex
		} else if strings.has_suffix(entry.name, ".frag") {
			shader.desc.stage = .Fragment
		} else if strings.has_suffix(entry.name, ".comp") {
			shader.desc.stage = .Compute
		} else {
			log.warnf("Unknown shader type %s...", entry.name)
			common.ref_free(&G_SHADER_REF_ARRAY, shader_ref)
			return false
		}

		if create_shader(shader_ref) == false {
			common.ref_free(&G_SHADER_REF_ARRAY, shader_ref)
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
	shader := &g_resources.shaders[get_shader_idx(p_shader_ref)]
	shader_hash := calculate_hash_for_shader(&shader.desc)
	assert((shader_hash in INTERNAL.shader_by_hash) == false)
	if backend_create_shader(p_shader_ref) == false {
		destroy_shader(p_shader_ref)
		return false
	}
	INTERNAL.shader_by_hash[shader_hash] = p_shader_ref
	return true
}

//---------------------------------------------------------------------------//

allocate_shader_ref :: proc(p_name: common.Name) -> ShaderRef {
	ref := ShaderRef(common.ref_create(ShaderResource, &G_SHADER_REF_ARRAY, p_name))
	g_resources.shaders[get_shader_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_shader_idx :: #force_inline proc(p_ref: ShaderRef) -> u32 {
	return common.ref_get_idx(&G_SHADER_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_shader :: proc(p_ref: ShaderRef) {
	// @TODO remove from cache (shader_by_hash)
	shader := &g_resources.shaders[get_shader_idx(p_ref)]
	backend_destroy_shader(p_ref)
	for feature in shader.desc.features {
		delete(feature, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	delete(shader.desc.features, G_RENDERER_ALLOCATORS.resource_allocator)
	common.ref_free(&G_SHADER_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

find_shader_by_name :: proc {
	find_shader_by_name_name,
	find_shader_by_name_str,
}

//--------------------------------------------------------------------------//

find_shader_by_name_name :: proc(p_name: common.Name) -> ShaderRef {
	ref := common.ref_find_by_name(&G_SHADER_REF_ARRAY, p_name)
	if ref == InvalidShaderRef {
		return InvalidShaderRef
	}
	return ShaderRef(ref)
}

//--------------------------------------------------------------------------//

find_shader_by_name_str :: proc(p_name: string) -> ShaderRef {
	ref := common.ref_find_by_name(&G_SHADER_REF_ARRAY, common.create_name(p_name))
	if ref == InvalidShaderRef {
		return InvalidShaderRef
	}
	return ShaderRef(ref)
}

//--------------------------------------------------------------------------//

// Creates a new shader permutation using the base shader
create_shader_permutation :: proc(
	p_name: common.Name,
	p_base_shader_ref: ShaderRef,
	p_features: []string,
	p_merge_features: bool,
) -> ShaderRef {
	base_shader := &g_resources.shaders[get_shader_idx(p_base_shader_ref)]

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

	for feature, i in permutation_desc.features {
		permutation_desc.features[i] = strings.clone(
			feature,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}

	permutation_ref := allocate_shader_ref(p_name)
	permutation := &g_resources.shaders[get_shader_idx(permutation_ref)]

	permutation.desc = permutation_desc

	if create_shader(permutation_ref) {
		return permutation_ref
	}

	return InvalidShaderRef
}

//--------------------------------------------------------------------------//

@(private = "file")
calculate_hash_for_shader :: proc(p_shader_desc: ^ShaderDesc) -> u32 {
	h := hash.crc32(transmute([]u8)common.get_string(p_shader_desc.file_path))
	return h ~ common.hash_string_array(p_shader_desc.features)
}

//--------------------------------------------------------------------------//
