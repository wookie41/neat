
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

//---------------------------------------------------------------------------//

@(private = "file")
MATERIAL_PARAMS_BUFFER_SIZE :: 8 * common.MEGABYTE

@(private = "file")
INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT :: 64

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	material_params_buffer_ref: BufferRef,
	material_feature_by_name:   map[common.Name]MaterialFeature,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_FEATURE_TYPE_MAPPING := map[string]MaterialFeatureParamType {
	"float1"    = .Float1,
	"float2"    = .Float2,
	"float3"    = .Float3,
	"float4"    = .Float4,
	"int1"      = .Int1,
	"int2"      = .Int2,
	"int3"      = .Int3,
	"int4"      = .Int4,
	"Texture2D" = .Texture2D,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_FEATURE_TYPE_SIZE_MAPPING := map[MaterialFeatureParamType]u8 {
	"float1"    = .Float1,
	"float2"    = .Float2,
	"float3"    = .Float3,
	"float4"    = .Float4,
	"int1"      = .Int1,
	"int2"      = .Int2,
	"int3"      = .Int3,
	"int4"      = .Int4,
	"Texture2D" = .Texture2D,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialFeatureParamJSON :: struct {
	name: string,
	type: string,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialFeatureJSONEntry :: struct {
	name:   string,
	flag:   string,
	params: []MaterialFeatureParamJSON,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialFeature :: struct {
	name:   common.Name,
	flag:   common.Name,
	params: []MaterialFeatureParam,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialFeatureParamType :: enum {
	Float1,
	Float2,
	Float3,
	Float4,
	Int1,
	Int2,
	Int3,
	Int4,
	Texture2D,
}

//---------------------------------------------------------------------------//

MaterialFeatureParam :: struct {
	name: common.Name,
	type: MaterialFeatureParamType,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialTypeJSONEntry :: struct {
	name:            string,
	features:        []string,
	material_passes: []string `json:"materialPasses"`,
}

//---------------------------------------------------------------------------//

MaterialTypeDesc :: struct {
	name:                 common.Name,
	features:             []common.Name,
	material_passes_refs: []MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialTypeResource :: struct {
	desc:                           MaterialTypeDesc,
	next_material_instance_idx:     u32,
	max_material_instance_entries:  u32,
	free_material_instance_indices: [dynamic]u32,
	params_size_in_bytes:           u16,
	offset_per_param:               map[common.Name]u16,
}

//---------------------------------------------------------------------------//

MaterialTypeRef :: common.Ref(MaterialTypeResource)

//---------------------------------------------------------------------------//

InvalidMaterialTypeRef := MaterialTypeRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_TYPE_REF_ARRAY: common.RefArray(MaterialTypeResource)
@(private = "file")
G_MATERIAL_TYPE_RESOURCE_ARRAY: []MaterialTypeResource

//---------------------------------------------------------------------------//

init_material_types :: proc() -> bool {

	// Allocate memory for the material types
	G_MATERIAL_REF_ARRAY = common.ref_array_create(
		MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MATERIAL_RESOURCE_ARRAY = make(
		[]MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Create a buffer for material params
	INTERNAL.material_params_buffer_ref = allocate_buffer_ref(
		common.create_name("MaterialParamsBuffer"),
	)

	material_params_buffer := get_buffer(INTERNAL.material_params_buffer_ref)

	material_params_buffer.desc.flags = {.Dedicated}
	material_params_buffer.desc.size = MATERIAL_PARAMS_BUFFER_SIZE
	material_params_buffer.desc.usage = {.StorageBuffer}

	create_buffer(INTERNAL.material_params_buffer_ref) or_return

	load_material_features_from_config_file() or_return
	load_materials_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_types :: proc() {
	destroy_buffer(INTERNAL.material_params_buffer_ref)
}

//---------------------------------------------------------------------------//

create_material_type :: proc(p_material_ref: MaterialTypeRef) -> (result: bool) {
	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	material_type := get_material_type(p_material_ref)

	material_type.next_material_instance_idx = 0
	material_type.max_material_instance_entries = INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT
	material_type.free_material_instance_indices = make(
		[dynamic]u32,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Gather feature strings, calculate size for params
	material_feature_defines := []string{}
	material_type.params_size_in_bytes = 0

	if len(material_type.desc.features) > 0 {
		material_feature_defines = make(
			[]string,
			len(material_type.desc.features),
			temp_arena.allocator,
		)
	}

	offset_per_param := make(map[common.Name]u16, temp_arena.allocator)
	for feature_name, i in material_type.desc.features {

		feature_name_str := common.get_string(feature_name)
		feature := INTERNAL.material_feature_by_name[feature_name_str]
		material_feature_defines[i] = common.get_string(feature.flag)

		for param in feature.params {

			// Create a joined name by concatenating the feature name and param name, to avoid collisions
			param_name_full := strings.join(
				{feature_name_str, common.get_string(param.name)},
				".",
				temp_area.allocator,
			)
			param_name_full = strings.to_lower(param_name_full, temp_arena.allocator)

			offset_per_param[common.make_name(param_name_full)] =
				material_type.params_size_in_bytes

			switch param.type {
			case .Float1:
				material_type.params_size_in_bytes += sizeof(f32)
			case .Float2:
				material_type.params_size_in_bytes += sizeof(f32) * 2
			case .Float3:
				material_type.params_size_in_bytes += sizeof(f32) * 3
			case .Float4:
				material_type.params_size_in_bytes += sizeof(f32) * 4
			case .Int1:
				material_type.params_size_in_bytes += sizeof(u32)
			case .Int2:
				material_type.params_size_in_bytes += sizeof(u32) * 2
			case .Int3:
				material_type.params_size_in_bytes += sizeof(u32) * 3
			case .Int4:
				material_type.params_size_in_bytes += sizeof(u32) * 4
			case .Texture2D:
				material_type.params_size_in_bytes += sizeof(u32)
			}
		}
	}

	// Now that we have the features for the material type, it's time 
	// to compile the shaders for each material pass this material type is a part of
	for material_pass_ref in material_type.desc.material_passes_refs {
		material_pass := get_material_pass(material_pass_ref)

		// Combine defines from the material with defines for the material pass
		shader_defines, _ := slice.concatenate(
			{material_feature_defines, material_pass.desc.additional_feature_names},
			temp_arena.allocator,
		)
		
		material_pass.vertex_shader_ref = allocate_shader_ref(material_pass.desc.name)
		material_pass.fragment_shader_ref = allocate_shader_ref(material_pass.desc.name)

		vertex_shader := get_shader(material_pass.vertex_shader_ref)
		fragment_shader := get_shader(material_pass.fragment_shader_ref)

		vertex_shader.desc.features = shader_defines
		vertex_shader.desc.file_path = material_pass.desc.vertex_shader_path
		vertex_shader.desc.type = .VERTEX
		
		fragment_shader.desc.features = shader_defines
		fragment_shader.desc.file_path = material_pass.desc.fragment_shader_path
		fragment_shader.desc.type = .FRAGMENT

		// @TODO error handling
		success := create_shader(material_pass.vertex_shader_ref)
		assert(success)
		
		shader_created_successfully =create_shader(material_pass.vertex_shader_ref)
		assert(success)

		// Create the PSO
		material_pass.pipeline_ref = allocate_pipeline_ref(material_pass.desc.name)
		pipeline := get_pipeline(material_pass.pipeline_ref)

		pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
		pipeline.desc.vert_shader = material_pass.vertex_shader_ref
		pipeline.desc.frag_shader = material_pass.fragment_shader_ref
		pipeline.desc.vertex_layout = .Mesh

		success = create_graphics_pipeline(material_pass.pipeline_ref)
		assert(success)
	}


	allocate_material_params_buffer(material)

	return true
}

//---------------------------------------------------------------------------//

allocate_material_type_ref :: proc(p_name: common.Name) -> MaterialTypeRef {
	ref := MaterialTypeRef(
		common.ref_create(MaterialTypeResource, &G_MATERIAL_TYPE_REF_ARRAY, p_name),
	)
	get_material(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

get_material_type :: proc(p_ref: MaterialTypeRef) -> ^MaterialTypeResource {
	return &G_MATERIAL_RESOURCE_ARRAY[common.ref_get_idx(&G_MATERIAL_REF_ARRAY, p_ref)]
}

//--------------------------------------------------------------------------//

destroy_material_type :: proc(p_ref: MaterialTypeRef) {
	material_type := get_material_type(p_ref)

	delete(material_type.free_material_instance_indices)

	if len(material_type.offset_per_param) > 0 {
		delete(material_type.offset_per_param, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	if len(material_type.desc.features) > 0 {
		delete(material_type.desc.features, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	delete(material_type.desc.material_passes_refs, G_RENDERER_ALLOCATORS.resource_allocator)

	common.ref_free(&G_MATERIAL_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private = "file")
load_material_features_from_config_file :: proc() -> bool {

	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	material_features_config := "app_data/renderer/config/material_features.json"
	material_features_json_data, file_read_ok := os.read_entire_file(material_features_config)

	if file_read_ok == false {
		return false
	}

	// Parse the material features config file
	material_feature_json_entries: []MaterialFeatureJSONEntry
	if err := json.unmarshal(material_features_json_data, &material_feature_json_entries);
	   err != nil {
		log.errorf("Failed to read materials features json: %s\n", err)
		return false
	}

	INTERNAL.material_feature_by_name = make(
		map[common.Name]MaterialFeature,
		len(material_feature_json_entries),
		G_RENDERER_ALLOCATORS.main_allocator,
	)

	for material_feature_entry in material_feature_json_entries {

		assert(len(material_feature_entry.params) > 0)

		material_feature := MaterialFeature {
			name = common.create_name(material_feature_entry.name),
			flag = common.create_name(material_feature_entry.flag),
		}

		// @TODO remember to free this when reloading material types/features is added
		material_feature.params = make(
			[]MaterialFeatureParam,
			len(material_feature_entry.params),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for i in 0 ..< len(material_feature_entry.params) {
			material_feature.params[i].name = common.create_name(
				material_feature_entry.params[i].name,
			)
			material_feature.params[i].type = G_MATERIAL_FEATURE_TYPE_MAPPING(
				material_feature_entry.params[i].type,
			)
		}

		INTERNAL.material_feature_by_name[material_feature.name] = material_feature
	}

	return true
}

//--------------------------------------------------------------------------//

@(private = "file")
load_materials_from_config_file :: proc() -> bool {
	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	material_types_config := "app_data/renderer/config/material_types.json"
	material_types_json_data, file_read_ok := os.read_entire_file(material_types_config)

	if file_read_ok == false {
		return false
	}

	// Parse the material types config file
	material_type_json_entries: []MaterialTypeJSONEntry

	if err := json.unmarshal(material_types_json_data, &material_type_json_entries); err != nil {
		log.errorf("Failed to read material types json: %s\n", err)
		return false
	}

	for material_type_json_entry in material_type_json_entries {
		material_type_ref := allocate_material_type_ref(
			common.create_name(material_type_json_entry.name),
		)
		material_type := get_material_type(material_type_ref)
		material_type.desc.name = common.make_name(material_type_json_entry.name)

		// Features
		if len(material_type_json_entry.features) > 0 {
			material_type.desc.features = make(
				[]common.Name,
				len(material_type_json_entry.features),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		for feature, i in material_type_json_entry.features {
			if (feature in INTERNAL.material_feature_by_name) == false {
				log.warnf(
					"Unsupported feature '%s' encountered when loading material type '%s'\n",
					feature,
					material_type_json_entry.name,
				)
				material_type.desc.features[i] = common.EMPTY_NAME
				continue
			}

			material_type.desc.features[i] = common.create_name(feature)
		}

		// Material passes

		// A material has to be included in at least one material pass, otherwise something is off
		assert(len(material_type_json_entry.material_passes) > 0)
		material_type.desc.material_passes_refs = make(
			[]MaterialPassRef,
			len(material_type_json_entries.material_passes),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for material_pass, i in material_type_json_entry.material_passes {
			material_type.desc.material_passes_refs = common.create_name(material_pass)
		}

		assert(create_material_type(material_type_ref))
	}

	return true
}

//--------------------------------------------------------------------------//

@(private = "file")
allocate_material_params_buffer :: proc(
	p_material: ^MaterialResource,
) -> (
	bool,
	BufferSuballocation,
) {

	// Calculate how many int params we have
	num_int_records := 0
	num_components := 0

	for int_param in p_material.desc.int_params {
		num_components += int(int_param.num_components)
		if num_components >= 4 {
			num_int_records += 1
			num_components = num_components % 4
		}
	}

	// Calculate how many float params we have
	num_float_records := 0
	num_components = 0

	for float_param in p_material.desc.float_params {
		num_components += int(float_param.num_components)
		if num_components >= 4 {
			num_float_records += 1
			num_components = num_components % 4
		}
	}

	// Calculate how many textureparams we have
	num_texture_records := 0
	num_components = 0

	for texture_param in p_material.desc.texture_params {
		num_components += 1
		if num_components >= 4 {
			num_texture_records += 1
			num_components = num_components % 4
		}
	}

	num_records := num_int_records + num_float_records + num_texture_records
	if num_records == 0 {
		return true, {}
	}

	p_material.material_buffer_entry_size_in_bytes =
		u32(
			num_float_records * size_of(f32) +
			num_int_records * size_of(u32) +
			num_texture_records * size_of(u32),
		) *
		4

	initial_material_buffer_size :=
		p_material.material_buffer_entry_size_in_bytes * INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT

	// Suballocate a chunk of the material buffer 
	// where we will store material instance data
	success, suballocation := buffer_allocate(
		INTERNAL.material_params_buffer_ref,
		u32(initial_material_buffer_size),
	)

	if success == false {
		return false, {}
	}

	p_material.float_params_offset = u32(num_int_records * size_of(u32) * 4)

	return true, suballocation
}

//--------------------------------------------------------------------------//

// Allocates an entry in the material buffer. Grows the buffer it the entry cannot 
// fit into the current buffer anymore.
material_allocate_entry :: proc(p_material_ref: MaterialTypeRef) -> (u32, ^byte) {

	material := get_material(p_material_ref)
	material_buffer := get_buffer(INTERNAL.material_params_buffer_ref)

	// Check if we have some free entries in the free array 
	if len(material.free_material_instance_indices) > 0 {
		entry_idx := pop(&material.free_material_instance_indices)
		entry_ptr := mem.ptr_offset(
			material_buffer.mapped_ptr,
			material.params_buffer.offset +
			entry_idx * material.material_buffer_entry_size_in_bytes,
		)

		return entry_idx, entry_ptr
	}

	if material.next_material_instance_idx >= material.max_material_instance_entries {
		// @TODO grow the buffer and copy all of the data currently in there 
		// to a new material, preserving the indexes for current material instances
		assert(false)
	}

	entry_idx := material.next_material_instance_idx
	material.next_material_instance_idx += 1

	entry_ptr := mem.ptr_offset(
		material_buffer.mapped_ptr,
		material.params_buffer.offset + entry_idx * material.material_buffer_entry_size_in_bytes,
	)

	return entry_idx, entry_ptr
}

//--------------------------------------------------------------------------//

material_free_entry :: proc(p_material_ref: MaterialTypeRef, p_entry_idx: u32) {

	// @TODO shrink the buffer if less than half of the entries are used

	material := get_material(p_material_ref)

	append(&material.free_material_instance_indices, p_entry_idx)

	return
}

//--------------------------------------------------------------------------//
