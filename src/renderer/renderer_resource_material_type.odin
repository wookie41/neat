package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:container/bit_array"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"

@(private)
MaterialPassPushContants :: struct #packed {
	material_idx: u32,
}

//---------------------------------------------------------------------------//

@(private)
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

@(private) 
g_material_properties_buffer_ref: BufferRef

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	material_properties_mem_data:   []byte,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_TYPE_SHADING_MODEL_MAPPING := map[string]MaterialTypeShadingModel {
	"DefaultLit" = .DefaultLit,
}
//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_TYPE_PROPERTIES_MAPPING := map[string]typeid {
	"Default" = DefaultMaterialTypeProperties,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialPropertyJSONEntry :: struct {
	name:    string,
	type:    string,
	default: []f32,
}

//---------------------------------------------------------------------------//

@(private = "file")
MaterialTypeJSONEntry :: struct {
	name:                   string,
	shading_model:          string `json:"shadingModel"`,
	defines:                []string,
	flags:                  []string,
	properties_struct_type: string `json:"propertiesStructType"`,
	material_passes:        []string `json:"materialPasses"`,
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
	name:                   common.Name,
	shading_model:          MaterialTypeShadingModel,
	defines:                []common.Name,
	flag_names:             []common.Name,
	properties_struct_type: typeid,
	material_passes_refs:   []MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialTypeResource :: struct {
	desc:                               MaterialTypeDesc,
	properties_size_in_bytes:           u32,
	free_material_buffer_entries_array: bit_array.Bit_Array,
	properties_buffer_suballocation:    BufferSuballocation,
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

//---------------------------------------------------------------------------//

//16 byte alignment
DefaultMaterialTypeProperties :: struct #packed {
	albedo:             glsl.vec3, // 12 = 12
	albedo_image_id:    u32, // 4 = 16
	normal:             glsl.vec3, // 12 = 28
	roughness:          f32, // 4 = 32
	metalness:          f32, // 4 = 36
	occlusion:          f32, // 4 = 40
	normal_image_id:    u32, // 4 = 44
	roughness_image_id: u32, // 4 = 48
	metalness_image_id: u32, // 4 = 52
	occlusion_image_id: u32, // 4 = 56 
	flags:              u32, // 4 = 60
	_padding:           [4]byte,
}

//---------------------------------------------------------------------------//

init_material_types :: proc() -> bool {

	// Allocate memory for the material types
	G_MATERIAL_TYPE_REF_ARRAY = common.ref_array_create(
		MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.material_types = make_soa(
		#soa[]MaterialTypeResource,
		MAX_MATERIAL_TYPES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Allocate CPU memory for the materials data
	INTERNAL.material_properties_mem_data = make(
		[]byte,
		MATERIAL_PARAMS_BUFFER_SIZE,
		G_RENDERER_ALLOCATORS.main_allocator,
	)

	// Create a buffer for material properties
	g_material_properties_buffer_ref = allocate_buffer_ref(
		common.create_name("MaterialPropertiesBuffer"),
	)

	material_params_buffer := &g_resources.buffers[get_buffer_idx(g_material_properties_buffer_ref)]

	material_params_buffer.desc.flags = {.Dedicated}
	material_params_buffer.desc.size = MATERIAL_PARAMS_BUFFER_SIZE
	material_params_buffer.desc.usage = {.StorageBuffer, .TransferDst}

	create_buffer(g_material_properties_buffer_ref) or_return

	load_material_types_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_types :: proc() {
	destroy_buffer(g_material_properties_buffer_ref)
}

//---------------------------------------------------------------------------//

create_material_type :: proc(p_material_ref: MaterialTypeRef) -> (result: bool) {
	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)
	defer if result == false {
		common.ref_free(&G_MATERIAL_TYPE_REF_ARRAY, p_material_ref)
	}

	material_type := &g_resources.material_types[get_material_type_idx(p_material_ref)]

	// Find out how big the properties struct is using reflection
	material_type.properties_size_in_bytes = u32(
		reflect.size_of_typeid(material_type.desc.properties_struct_type),
	)

	// Suballocate the params buffer for this material type to store material instance data
	{
		success, suballocation := buffer_allocate(
			g_material_properties_buffer_ref,
			u32(material_type.properties_size_in_bytes * MAX_MATERIAL_INSTANCES_PER_MATERIAL_TYPE),
		)

		if success == false {
			return false
		}

		material_type.properties_buffer_suballocation = suballocation
	}


	material_type_defines := make([]string, len(material_type.desc.defines), temp_arena.allocator)
	for define, i in material_type.desc.defines {
		material_type_defines[i] = common.get_string(define)
	}

	// Compile the shaders for each material passes that use this material
	for material_pass_ref in material_type.desc.material_passes_refs {
		material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]

		// Combine defines from the material with defines for the material pass
		shader_defines, _ := slice.concatenate(
			[][]string{material_type_defines, material_pass.desc.additional_feature_names},
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
		material_pass.pipeline_ref = allocate_pipeline_ref(material_pass.desc.name, 3, 1)
		pipeline := &g_resources.pipelines[get_pipeline_idx(material_pass.pipeline_ref)]
		pipeline.desc.bind_group_layout_refs = {
			InvalidBindGroupRefLayout, // Slot 0 not used
			G_RENDERER.global_bind_group_layout_ref,
			G_RENDERER.bindless_textures_array_bind_group_layout_ref,
		}

		pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
		pipeline.desc.vert_shader_ref = material_pass.vertex_shader_ref
		pipeline.desc.frag_shader_ref = material_pass.fragment_shader_ref
		pipeline.desc.vertex_layout = .Mesh

		pipeline.desc.push_constants[0] = PushConstantDesc {
			offset_in_bytes = 0,
			size_in_bytes = size_of(MaterialPassPushContants),
			shader_stages = {.Fragment},
		}

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
	g_resources.material_types[get_material_type_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

get_material_type_idx :: #force_inline proc(p_ref: MaterialTypeRef) -> u32 {
	return common.ref_get_idx(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material_type :: proc(p_ref: MaterialTypeRef) {
	material_type := &g_resources.material_types[get_material_type_idx(p_ref)]

	bit_array.destroy(&material_type.free_material_buffer_entries_array)

	if len(material_type.desc.defines) > 0 {
		delete(material_type.desc.defines, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	if len(material_type.desc.flag_names) > 0 {
		delete(material_type.desc.flag_names, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	delete(material_type.desc.material_passes_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	buffer_free(
		g_material_properties_buffer_ref,
		material_type.properties_buffer_suballocation.vma_allocation,
	)

	common.ref_free(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private = "file")
load_material_types_from_config_file :: proc() -> bool {
	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

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

		material_type := &g_resources.material_types[get_material_type_idx(material_type_ref)]
		material_type.desc.name = common.create_name(material_type_json_entry.name)

		// Shading model
		assert(material_type_json_entry.shading_model in G_MATERIAL_TYPE_SHADING_MODEL_MAPPING)
		material_type.desc.shading_model =
			G_MATERIAL_TYPE_SHADING_MODEL_MAPPING[material_type_json_entry.shading_model]

		// Flags
		material_type.desc.flag_names = make(
			[]common.Name,
			len(material_type_json_entry.flags),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for flag, i in material_type_json_entry.flags {
			material_type.desc.flag_names[i] = common.create_name(flag)
		}

		// Defines
		material_type.desc.defines = make(
			[]common.Name,
			len(material_type_json_entry.defines),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for define, i in material_type_json_entry.defines {
			material_type.desc.defines[i] = common.create_name(define)
		}

		// Properties struct
		assert(
			material_type_json_entry.properties_struct_type in G_MATERIAL_TYPE_PROPERTIES_MAPPING,
		)
		material_type.desc.properties_struct_type =
			G_MATERIAL_TYPE_PROPERTIES_MAPPING[material_type_json_entry.properties_struct_type]


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

material_type_allocate_properties_entry :: proc(
	p_material_type_ref: MaterialTypeRef,
) -> (
	u32,
	^byte,
) {

	material_type := &g_resources.material_types[get_material_type_idx(p_material_type_ref)]

	// Check if we have some free entries in the free array 
	it := bit_array.make_iterator(&material_type.free_material_buffer_entries_array)
	free_entry_idx, has_free_entry := bit_array.iterate_by_set(&it)
	if !has_free_entry {
		return 0, nil
	}

	bit_array.unset(&material_type.free_material_buffer_entries_array, free_entry_idx)

	entry_ptr := mem.ptr_offset(
		raw_data(INTERNAL.material_properties_mem_data),
		material_type.properties_buffer_suballocation.offset +
		u32(free_entry_idx) * u32(material_type.properties_size_in_bytes),
	)

	return u32(free_entry_idx), entry_ptr
}

//--------------------------------------------------------------------------//

material_type_free_properties_entry :: proc(
	p_material_type_ref: MaterialTypeRef,
	p_entry_idx: u32,
) {
	material_type := &g_resources.material_types[get_material_type_idx(p_material_type_ref)]
	bit_array.set(&material_type.free_material_buffer_entries_array, p_entry_idx)
	return
}

//--------------------------------------------------------------------------//

find_material_type :: proc {
	find_material_type_by_name,
	find_material_type_by_str,
}

find_material_type_by_name :: proc(p_name: common.Name) -> MaterialTypeRef {
	ref := common.ref_find_by_name(&G_MATERIAL_TYPE_REF_ARRAY, p_name)
	if ref == InvalidMaterialTypeRef {
		return InvalidMaterialTypeRef
	}
	return MaterialTypeRef(ref)
}

//--------------------------------------------------------------------------//

find_material_type_by_str :: proc(p_str: string) -> MaterialTypeRef {
	return find_material_type_by_name(common.create_name(p_str))
}

//--------------------------------------------------------------------------//
