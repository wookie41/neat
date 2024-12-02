package renderer

// @TODO Figure out when we should free the shader, as they can be used by
// multiple material instances. For now we always keep them loaded

//---------------------------------------------------------------------------//

import "core:c"
import "core:encoding/json"
import "core:hash"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf16"
import "core:sys/windows"

import "../common"

//---------------------------------------------------------------------------//

BASE_SHADERS_PATH :: "app_data/renderer/assets/shaders/"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	shader_by_hash:       map[u32]ShaderRef,
	shaders_dir_handle:   windows.HANDLE,
	windows_event_handle: windows.HANDLE,
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
	Pixel,
	Compute,
}

ShaderStageFlags :: distinct bit_set[ShaderStage;u8]

//---------------------------------------------------------------------------//

ShaderFlagBits :: enum u16 {}

ShaderFlags :: distinct bit_set[ShaderFlagBits;u16]

//---------------------------------------------------------------------------//

ShaderResource :: struct {
	desc:           ShaderDesc,
	flags:          ShaderFlags,
	hash:           u32,
	included_files: []string,
}

//---------------------------------------------------------------------------//

ShaderRef :: common.Ref(ShaderResource)

//---------------------------------------------------------------------------//

InvalidShaderRef := ShaderRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

init_shaders :: proc() -> bool {
	g_resource_refs.shaders = common.ref_array_create(
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

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE * 2)
	defer common.arena_delete(temp_arena)

	// Load base shader permutations
	shaders_config := "app_data/renderer/config/shaders.json"
	shaders_json_data, file_read_ok := os.read_entire_file(shaders_config, temp_arena.allocator)

	if file_read_ok == false {
		log.error("Failed to open the shaders config file")
		return false
	}

	shader_json_entries: []ShaderJSONEntry

	// Make sure that the bin and reflect dirs exist
	{
		dirs := []string {
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
	if err := json.unmarshal(
		shaders_json_data,
		&shader_json_entries,
		.JSON5,
		temp_arena.allocator,
	); err != nil {
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
		} else if strings.has_suffix(entry.name, ".pix") {
			shader.desc.stage = .Pixel
		} else if strings.has_suffix(entry.name, ".comp") {
			shader.desc.stage = .Compute
		} else {
			log.warnf("Unknown shader type %s...", entry.name)
			common.ref_free(&g_resource_refs.shaders, shader_ref)
			return false
		}

		if create_shader(shader_ref) == false {
			common.ref_free(&g_resource_refs.shaders, shader_ref)
			continue
		}
	}

	init_shader_files_watcher()

	return backend_init_shaders()
}

//---------------------------------------------------------------------------//

deinit_shaders :: proc() {
	backend_deinit_shaders()
}

//---------------------------------------------------------------------------//

create_shader :: proc(p_shader_ref: ShaderRef) -> bool {
	shader := &g_resources.shaders[get_shader_idx(p_shader_ref)]
	shader.hash = calculate_hash_for_shader(&shader.desc)
	assert((shader.hash in INTERNAL.shader_by_hash) == false)

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	shader_code := shader_compile(p_shader_ref, temp_arena.allocator) or_return

	if backend_create_shader(p_shader_ref, shader_code) == false {
		destroy_shader(p_shader_ref)
		return false
	}

	INTERNAL.shader_by_hash[shader.hash] = p_shader_ref
	return true
}

//---------------------------------------------------------------------------//

allocate_shader_ref :: proc(p_name: common.Name) -> ShaderRef {
	ref := ShaderRef(common.ref_create(ShaderResource, &g_resource_refs.shaders, p_name))
	g_resources.shaders[get_shader_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_shader_idx :: #force_inline proc(p_ref: ShaderRef) -> u32 {
	return common.ref_get_idx(&g_resource_refs.shaders, p_ref)
}

//--------------------------------------------------------------------------//

destroy_shader :: proc(p_ref: ShaderRef) {
	// @TODO remove from cache (shader_by_hash)
	shader := &g_resources.shaders[get_shader_idx(p_ref)]
	backend_destroy_shader(p_ref)
	for feature in shader.desc.features {
		delete(feature, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	delete(shader.included_files, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(shader.desc.features, G_RENDERER_ALLOCATORS.resource_allocator)
	common.ref_free(&g_resource_refs.shaders, p_ref)
}

//--------------------------------------------------------------------------//

find_shader_by_name :: proc {
	find_shader_by_name_name,
	find_shader_by_name_str,
}

//--------------------------------------------------------------------------//

find_shader_by_name_name :: proc(p_name: common.Name) -> ShaderRef {
	ref := common.ref_find_by_name(&g_resource_refs.shaders, p_name)
	if ref == InvalidShaderRef {
		return InvalidShaderRef
	}
	return ShaderRef(ref)
}

//--------------------------------------------------------------------------//

find_shader_by_name_str :: proc(p_name: string) -> ShaderRef {
	ref := common.ref_find_by_name(&g_resource_refs.shaders, common.create_name(p_name))
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
	return h ~ common.hash_string_array(p_shader_desc.features) ~ u32(p_shader_desc.stage)
}

//--------------------------------------------------------------------------//

@(private = "file")
init_shader_files_watcher :: proc() -> bool {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	shaders_dir_path := windows.utf8_to_wstring(
		"app_data/renderer/assets/shaders",
		temp_arena.allocator,
	)

	INTERNAL.shaders_dir_handle = windows.CreateFileW(
		shaders_dir_path,
		windows.FILE_LIST_DIRECTORY,
		windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
		nil,
		windows.OPEN_EXISTING,
		windows.FILE_FLAG_BACKUP_SEMANTICS | windows.FILE_FLAG_OVERLAPPED,
		nil,
	)

	INTERNAL.windows_event_handle = windows.CreateEventW(nil, false, false, nil)

	return true
}

//--------------------------------------------------------------------------//

@(private)
shaders_update :: proc() {

	overlapped := windows.OVERLAPPED {
		hEvent = INTERNAL.windows_event_handle,
	}

	// Read directory changes
	change_buffer: [1024]byte
	success := windows.ReadDirectoryChangesW(
		INTERNAL.shaders_dir_handle,
		&change_buffer[0],
		len(change_buffer),
		true,
		windows.FILE_NOTIFY_CHANGE_LAST_WRITE,
		nil,
		&overlapped,
		nil,
	)
	if success == false {
		return
	}

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	for {
		result := windows.WaitForSingleObject(overlapped.hEvent, 1)
		if result == windows.WAIT_FAILED {
			log.warn("Failed to wait for shaders dir changes")
			return
		}

		if result == windows.WAIT_OBJECT_0 {
			bytes_transferred: windows.DWORD
			windows.GetOverlappedResult(
				INTERNAL.shaders_dir_handle,
				&overlapped,
				&bytes_transferred,
				false,
			)

			event := (^windows.FILE_NOTIFY_INFORMATION)(&change_buffer[0])
			file_name_len := int(event.file_name_length)
			file_name_w := windows.wstring(&event.file_name[0])
			file_name, err := windows.wstring_to_utf8(
				file_name_w,
				(file_name_len / size_of(windows.wchar_t)),
				temp_arena.allocator,
			)

			if err == nil {
				reload_shader(file_name)
			}

			if event.next_entry_offset == 0 {
				break
			}

			event = (^windows.FILE_NOTIFY_INFORMATION)(
				uintptr(event) + uintptr(event.next_entry_offset),
			)

			continue
		}

		break
	}
}

//--------------------------------------------------------------------------//

@(private = "file")
reload_shader :: proc(p_shader_file_name: string) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	if strings.contains(p_shader_file_name, "incl") {
		// ignore include files
		return
	}

	shader_name := common.create_name(p_shader_file_name)

	// Find the shader for this file name
	for i in 0 ..< g_resource_refs.shaders.alive_count {
		shader_ref := g_resource_refs.shaders.alive_refs[i]
		shader := &g_resources.shaders[get_shader_idx(shader_ref)]

		if shader_name != shader.desc.file_path {
			continue
		}

		shader_code, ok := shader_compile(shader_ref, temp_arena.allocator)

		if ok == false {
			log.warnf(
				"Failed to hot reload shader '%s' - the source probably contains errors\n",
				p_shader_file_name,
			)
			return
		}

		if backend_reload_shader(shader_ref, shader_code) == false {
			return
		}

		// Find all graphics pipelines referencing this shader
		num_reloaded_pipelines: u32 = 0

		if shader.desc.stage == .Compute {
			for j in 0 ..< g_resource_refs.compute_pipelines.alive_count {
				pipeline_ref := g_resource_refs.compute_pipelines.alive_refs[j]
				pipeline := &g_resources.compute_pipelines[get_compute_pipeline_idx(pipeline_ref)]

				if pipeline.desc.compute_shader_ref == shader_ref {
					compute_pipeline_reset(pipeline_ref)
					compute_pipeline_create(pipeline_ref)
					num_reloaded_pipelines += 1
				}
			}
		} else {
			for j in 0 ..< g_resource_refs.graphics_pipelines.alive_count {
				pipeline_ref := g_resource_refs.graphics_pipelines.alive_refs[j]
				pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(pipeline_ref)]

				if pipeline.desc.vert_shader_ref == shader_ref ||
				   pipeline.desc.frag_shader_ref == shader_ref {
					graphics_pipeline_reset(pipeline_ref)
					graphics_pipeline_create(pipeline_ref)
					num_reloaded_pipelines += 1
				}
			}
		}

		log.infof(
			"Shader '%s' reloaded, along with %d pipelines\n",
			p_shader_file_name,
			num_reloaded_pipelines,
		)

		return
	}
}

//--------------------------------------------------------------------------//

@(private = "file")
shader_compile :: proc(
	p_shader_ref: ShaderRef,
	p_shader_code_allocator: mem.Allocator,
) -> (
	[]byte,
	bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	shader := &g_resources.shaders[get_shader_idx(p_shader_ref)]

	shader_stage := ""
	shader_suffix := ""
	switch shader.desc.stage {
	case .Vertex:
		shader_stage = "vert"
		shader_suffix = "vert.hlsl"
	case .Pixel:
		shader_stage = "pix"
		shader_suffix = "pix.hlsl"
	case .Compute:
		shader_stage = "comp"
		shader_stage = "comp.hlsl"
	case:
		assert(false, "Unsupported shader type")
	}

	shader_path := common.get_string(shader.desc.file_path)
	shader_bin_path_base := shader_path

	// Vertex and pixel shaders shader the same file, so we add the stage
	// suffix here to compile the shader with differnt entry points
	if !strings.contains(shader_path, shader_stage) {
		shader_bin_path_base, _ = strings.replace(shader_path, "hlsl", shader_suffix, 1, temp_arena.allocator)
	}

	shader_src_path := common.aprintf(
		temp_arena.allocator,
		"app_data/renderer/assets/shaders/%s",
		shader_path,
	)

	// Find out the last time the shader was modified. It's used to determine 
	// if the compiled version is up to date
	last_shader_write_time := common.get_last_file_write_time(shader_src_path)
	
	// @TODO disable once we also keep track of the changes to include files
	shader_cache_enabled := false

	shader_bin_path := common.aprintf(
		temp_arena.allocator,
		"app_data/renderer/assets/shaders/%s/%s-%d.%s",
		BACKEND_COMPILED_SHADERS_FOLDER,
		shader_bin_path_base,
		last_shader_write_time._nsec,
		BACKEND_COMPILED_SHADERS_EXTENSION,
	)

	if !os.exists(shader_bin_path) || !shader_cache_enabled {

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

		log.infof("Compiling shader %s with features %s\n", shader_src_path, shader_defines_log)

		if backend_compile_shader(
			   shader_src_path,
			   shader_bin_path,
			   shader.desc.stage,
			   shader_defines,
		   ) ==
		   false {
			return nil, false
		}
	}

	// Remove old version of the shader binary
	shader_bins_search_path := common.aprintf(
		temp_arena.allocator,
		"app_data/renderer/assets/shaders/%s/%s-*",
		BACKEND_COMPILED_SHADERS_FOLDER,
		shader_bin_path_base,
	)
	
	path_w := windows.utf8_to_wstring(shader_bins_search_path, temp_arena.allocator)

	find_file_data := windows.WIN32_FIND_DATAW{}
	file_handle := windows.FindFirstFileW(path_w, &find_file_data)
	
	timestamp_str := common.aprintf(temp_arena.allocator, "%i", last_shader_write_time._nsec)

	// Loop over all of the files in the directory whose name matches the pattern
	if file_handle != windows.INVALID_HANDLE_VALUE {

		path_buffer := make([]byte, windows.MAX_PATH, temp_arena.allocator)

		for  {

			path_len := utf16.decode_to_utf8(path_buffer, find_file_data.cFileName[:])
			path := string(path_buffer[:path_len])
			
			// Delete if it's not the latest version
			if !strings.contains(path, timestamp_str) {

				delete_path := common.aprintf(
					temp_arena.allocator,
					"app_data/renderer/assets/shaders/%s/%s",
					BACKEND_COMPILED_SHADERS_FOLDER,
					path,
				)

				os.remove(delete_path)
			}

			
			if windows.FindNextFileW(file_handle, &find_file_data) == false {
				break
			}
		}
	
	}

	// Read the shader binary
	return os.read_entire_file(shader_bin_path, p_shader_code_allocator)
}

//--------------------------------------------------------------------------//
