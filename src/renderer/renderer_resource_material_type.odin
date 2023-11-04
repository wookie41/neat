package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:container/bit_array"
import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

//---------------------------------------------------------------------------//

@(private = "file")
MATERIAL_PARAMS_BUFFER_SIZE :: 8 * common.MEGABYTE

// @TODO 
// Right now we just allocate a constant number, but some material types 
// will be more frequently used than others, so we should handle it more smartly
// by dynamically resizing the material type buffer section when more instances come
// and go. This should be faily easy, as we always just bind a single material buffer
// with a per material type offset and access the material with an index
@(private = "file")
MAX_MATERIAL_INSTANCES_PER_MATERIAL_TYPE :: 512

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
G_MATERIAL_TYPE_SHADING_MODEL_MAPPING := map[string]MaterialTypeShadingModel {
	"DefaultLit" = .DefaultLit,
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
	shading_model:   string `json:"shadingModel"`,
	features:        []string,
	material_passes: []string `json:"materialPasses"`,
}

//---------------------------------------------------------------------------//

// The shading model is used to determine in which render passes the 
// material passes for this materials should be placed in
// eg. DefaultLit will go through the deferred path for a deferred renderer 
// but transparent will be placed in the forward render pass
MaterialTypeShadingModel :: enum {
	DefaultLit,
}

//---------------------------------------------------------------------------//

MaterialTypeDesc :: struct {
	name:                 common.Name,
	shading_model:        MaterialTypeShadingModel,
	features:             []common.Name,
	material_passes_refs: []MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialTypeResource :: struct {
	desc:                               MaterialTypeDesc,
	params_size_in_bytes:               u16,
	free_material_buffer_entries_array: bit_array.Bit_Array,
	params_buffer_suballocation:        BufferSuballocation,
	offset_per_param:                   map[common.Name]u16,
}

//---------------------------------------------------------------------------//

MaterialTypeRef :: common.Ref(MaterialTypeResource)

//---------------------------------------------------------------------------//

InvalidMaterialTypeRef := MaterialTypeRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_TYPE_REF_ARRAY: common.RefArray(MaterialTypeResource)
@(private = "file")
G_MATERIAL_TYPE_RESOURCE_ARRAY: []MaterialTypeResource

//---------------------------------------------------------------------------//

init_material_types :: proc() -> bool {

	// Allocate memory for the material types
	G_MATERIAL_TYPE_REF_ARRAY = common.ref_array_create(
		MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MATERIAL_TYPE_RESOURCE_ARRAY = make(
		[]MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Create a buffer for material params
	INTERNAL.material_params_buffer_ref = allocate_buffer_ref(
		common.create_name("MaterialParamsBuffer"),
	)

	material_params_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.material_params_buffer_ref)]

	material_params_buffer.desc.flags = {.Dedicated}
	material_params_buffer.desc.size = MATERIAL_PARAMS_BUFFER_SIZE
	material_params_buffer.desc.usage = {.DynamicStorageBuffer}

	create_buffer(INTERNAL.material_params_buffer_ref) or_return

	load_material_features_from_config_file() or_return
	load_material_types_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_types :: proc() {
	destroy_buffer(INTERNAL.material_params_buffer_ref)
}

//---------------------------------------------------------------------------//

create_material_type :: proc(p_material_ref: MaterialTypeRef) -> (result: bool) {
	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)
	defer if result == false {
		common.ref_free(&G_MATERIAL_TYPE_REF_ARRAY, p_material_ref)
	}

	material_type := get_material_type(p_material_ref)

	// Gather feature strings, calculate size for the paramteres
	material_feature_defines := []string{}
	material_type.params_size_in_bytes = 0

	if len(material_type.desc.features) > 0 {
		material_feature_defines = make(
			[]string,
			len(material_type.desc.features),
			temp_arena.allocator,
		)
	}

	offset_per_param := make(map[common.Name]u16, 32, temp_arena.allocator)

	// Iterate over all features, saving the offset for each param and create an unique, per param name
	for feature_name, i in material_type.desc.features {

		feature := INTERNAL.material_feature_by_name[feature_name]
		material_feature_defines[i] = common.get_string(feature.flag)

		for param in feature.params {

			// Create a joined name by concatenating the feature name and param name to avoid collisions
			feature_name_str := common.get_string(feature_name)
			param_name_full := strings.join(
				{feature_name_str, common.get_string(param.name)},
				".",
				temp_arena.allocator,
			)
			param_name_full = strings.to_lower(param_name_full, temp_arena.allocator)

			offset_per_param[common.create_name(param_name_full)] =
				material_type.params_size_in_bytes

			switch param.type {
			case .Float1:
				material_type.params_size_in_bytes += size_of(f32)
			case .Float2:
				material_type.params_size_in_bytes += size_of(f32) * 2
			case .Float3:
				material_type.params_size_in_bytes += size_of(f32) * 3
			case .Float4:
				material_type.params_size_in_bytes += size_of(f32) * 4
			case .Int1:
				material_type.params_size_in_bytes += size_of(u32)
			case .Int2:
				material_type.params_size_in_bytes += size_of(u32) * 2
			case .Int3:
				material_type.params_size_in_bytes += size_of(u32) * 3
			case .Int4:
				material_type.params_size_in_bytes += size_of(u32) * 4
			case .Texture2D:
				material_type.params_size_in_bytes += size_of(u32)
			}
		}
	}

	// Suballocate the params buffer for this material type
	// to store material instance data
	{
		success, suballocation := buffer_allocate(
			INTERNAL.material_params_buffer_ref,
			u32(material_type.params_size_in_bytes * MAX_MATERIAL_INSTANCES_PER_MATERIAL_TYPE),
		)

		if success == false {
			return false
		}

		material_type.params_buffer_suballocation = suballocation
	}

	// Now that we have the features for the material type, it's time 
	// to compile the shaders for each material passes that use this material
	for material_pass_ref in material_type.desc.material_passes_refs {
		material_pass := get_material_pass(material_pass_ref)

		// Combine defines from the material with defines for the material pass
		shader_defines, _ := slice.concatenate(
			[][]string{material_feature_defines, material_pass.desc.additional_feature_names},
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		vert_shader_path := common.get_string(material_pass.desc.vertex_shader_path)
		vert_shader_path = strings.trim_suffix(vert_shader_path, ".hlsl")

		frag_shader_path := common.get_string(material_pass.desc.fragment_shader_path)
		frag_shader_path = strings.trim_suffix(frag_shader_path, ".hlsl")

		material_pass.vertex_shader_ref = allocate_shader_ref(common.create_name(vert_shader_path))
		material_pass.fragment_shader_ref = allocate_shader_ref(
			common.create_name(frag_shader_path),
		)

		vertex_shader := &g_resources.shaders[get_shader_idx(material_pass.vertex_shader_ref)]
		fragment_shader := &g_resources.shaders[get_shader_idx(material_pass.fragment_shader_ref)]

		vertex_shader.desc.features = shader_defines
		vertex_shader.desc.file_path = material_pass.desc.vertex_shader_path
		vertex_shader.desc.stage = .Vertex

		fragment_shader.desc.features = shader_defines
		fragment_shader.desc.file_path = material_pass.desc.fragment_shader_path
		fragment_shader.desc.stage = .Fragment

		// @TODO error handling
		success := create_shader(material_pass.vertex_shader_ref)
		assert(success)

		success = create_shader(material_pass.fragment_shader_ref)
		assert(success)

		// Create the PSO
		material_pass.pipeline_ref = allocate_pipeline_ref(material_pass.desc.name, 3)
		pipeline := &g_resources.pipelines[get_pipeline_idx(material_pass.pipeline_ref)]
		pipeline.desc.bind_group_layout_refs = {
			InvalidBindGroupLayout, // @TODO material bind group
			G_RENDERER.global_bind_group_layout_ref,
			G_RENDERER.bindless_textures_array_bind_group_layout_ref,
		}

		pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
		pipeline.desc.vert_shader_ref = material_pass.vertex_shader_ref
		pipeline.desc.frag_shader_ref = material_pass.fragment_shader_ref
		pipeline.desc.vertex_layout = .Mesh

		success = create_graphics_pipeline(material_pass.pipeline_ref)
		assert(success)
	}

	// Initialize the bitarray the will allow to quickly lookup free material entries
	common.bit_array_init(
		&material_type.free_material_buffer_entries_array,
		MAX_MATERIAL_INSTANCES_PER_MATERIAL_TYPE,
		0,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	for i in 0 ..< MAX_MATERIAL_INSTANCES_PER_MATERIAL_TYPE {
		bit_array.unsafe_set(&material_type.free_material_buffer_entries_array, i)
	}

	return true
}

//---------------------------------------------------------------------------//

allocate_material_type_ref :: proc(p_name: common.Name) -> MaterialTypeRef {
	ref := MaterialTypeRef(
		common.ref_create(MaterialTypeResource, &G_MATERIAL_TYPE_REF_ARRAY, p_name),
	)
	get_material_type(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

get_material_type :: proc(p_ref: MaterialTypeRef) -> ^MaterialTypeResource {
	return &G_MATERIAL_TYPE_RESOURCE_ARRAY[common.ref_get_idx(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)]
}

//--------------------------------------------------------------------------//

destroy_material_type :: proc(p_ref: MaterialTypeRef) {
	material_type := get_material_type(p_ref)

	bit_array.destroy(&material_type.free_material_buffer_entries_array)

	if len(material_type.offset_per_param) > 0 {
		delete(material_type.offset_per_param)
	}

	if len(material_type.desc.features) > 0 {
		delete(material_type.desc.features, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	delete(material_type.desc.material_passes_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	buffer_free(
		INTERNAL.material_params_buffer_ref,
		material_type.params_buffer_suballocation.vma_allocation,
	)

	common.ref_free(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private = "file")
load_material_features_from_config_file :: proc() -> bool {
	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)

	material_features_config := "app_data/renderer/config/material_features.json"
	material_features_json_data, file_read_ok := os.read_entire_file(
		material_features_config,
		temp_arena.allocator,
	)

	if file_read_ok == false {
		return false
	}

	// Parse the material features config file
	material_feature_json_entries: []MaterialFeatureJSONEntry
	if err := json.unmarshal(
		material_features_json_data,
		&material_feature_json_entries,
		.JSON5,
		temp_arena.allocator,
	); err != nil {
		log.errorf("Failed to read materials features json: %s\n", err)
		return false
	}

	INTERNAL.material_feature_by_name = make(
		map[common.Name]MaterialFeature,
		len(material_feature_json_entries),
		G_RENDERER_ALLOCATORS.main_allocator,
	)

	for material_feature_entry in &material_feature_json_entries {

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
			material_feature.params[i].type =
				G_MATERIAL_FEATURE_TYPE_MAPPING[material_feature_entry.params[i].type]
		}

		INTERNAL.material_feature_by_name[material_feature.name] = material_feature
	}

	return true
}

//--------------------------------------------------------------------------//

@(private = "file")
load_material_types_from_config_file :: proc() -> bool {
	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)

	material_types_config := "app_data/renderer/config/material_types.json"
	material_types_json_data, file_read_ok := os.read_entire_file(
		material_types_config,
		temp_arena.allocator,
	)

	if file_read_ok == false {
		return false
	}

	// Parse the material types config file
	material_type_json_entries: []MaterialTypeJSONEntry

	if err := json.unmarshal(
		material_types_json_data,
		&material_type_json_entries,
		.JSON5,
		temp_arena.allocator,
	); err != nil {
		log.errorf("Failed to read material types json: %s\n", err)
		return false
	}

	for material_type_json_entry in material_type_json_entries {
		material_type_ref := allocate_material_type_ref(
			common.create_name(material_type_json_entry.name),
		)
		material_type := get_material_type(material_type_ref)
		material_type.desc.name = common.create_name(material_type_json_entry.name)

		// Shading model
		assert(material_type_json_entry.shading_model in G_MATERIAL_TYPE_SHADING_MODEL_MAPPING)
		material_type.desc.shading_model =
			G_MATERIAL_TYPE_SHADING_MODEL_MAPPING[material_type_json_entry.shading_model]

		// Features
		if len(material_type_json_entry.features) > 0 {
			material_type.desc.features = make(
				[]common.Name,
				len(material_type_json_entry.features),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		// Rewrite features from the JSON representation and check if all are supported
		for feature, i in material_type_json_entry.features {
			if (common.create_name(feature) in INTERNAL.material_feature_by_name) == false {
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

		// A material has to be included in at least one material pass, otherwise something is off
		assert(len(material_type_json_entry.material_passes) > 0)

		// Gather all of the material passes this material is a part of 
		material_type.desc.material_passes_refs = make(
			[]MaterialPassRef,
			len(material_type_json_entry.material_passes),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for material_pass, i in material_type_json_entry.material_passes {
			pass_name := common.create_name(material_pass)
			material_type.desc.material_passes_refs[i] = find_material_pass_by_name(pass_name)
			assert(material_type.desc.material_passes_refs[i] != InvalidMaterialPassRef)
		}

		assert(create_material_type(material_type_ref))
	}

	return true
}

//--------------------------------------------------------------------------//

material_type_allocate_params_entry :: proc(p_material_type_ref: MaterialTypeRef) -> (u32, ^byte) {

	material_type := get_material_type(p_material_type_ref)
	material_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.material_params_buffer_ref)]

	// Check if we have some free entries in the free array 
	it := bit_array.make_iterator(&material_type.free_material_buffer_entries_array)
	free_entry_idx, has_free_entry := bit_array.iterate_by_set(&it)
	if !has_free_entry {
		return 0, nil
	}

	bit_array.unset(&material_type.free_material_buffer_entries_array, free_entry_idx)

	entry_ptr := mem.ptr_offset(
		material_buffer.mapped_ptr,
		material_type.params_buffer_suballocation.offset +
		u32(free_entry_idx) * u32(material_type.params_size_in_bytes),
	)

	return u32(free_entry_idx), entry_ptr
}

//--------------------------------------------------------------------------//

material_type_free_params_entry :: proc(p_material_type_ref: MaterialTypeRef, p_entry_idx: u32) {
	material_type := get_material_type(p_material_type_ref)
	bit_array.set(&material_type.free_material_buffer_entries_array, p_entry_idx)
	return
}

//--------------------------------------------------------------------------//
