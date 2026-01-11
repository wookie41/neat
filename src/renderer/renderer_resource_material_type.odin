package renderer

//---------------------------------------------------------------------------//


/*

The material system consist of three parts:

MaterialType - serves as as bridge between a MaterialInstance and a MaterialPass that dictates
if a mesh with a particular MaterialInstance should be drawn into a MaterialPass. 
All MaterialTypes share the same paramters set for simplicity (uber-shader approach), but how they use
and interpert them is dictated by the MaterialPass itself.

MaterialPass - grabs the (vertex/pixel) shader inputs, the material data buffer and resolves the material paramters.
The MaterialPass is free to use all or none of the material parameters to resolve the material paramters, it 
can also just use constant data.
A MaterialPass itself doesn't know anything about the underyling pipeline though, as for gbuffer and shadows we'll
have different render targets layouts and so on. That's where MaterialPassType comes in. When a MaterialPass has to be 
renderer for a particular pass type, that's when the PSO for the MaterialPass is compiled.

*/


import "../common"

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"

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
	defines:              []common.Name,
	material_passes_refs: []MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialTypeResource :: struct {
	name:                 common.Name,
	desc:               MaterialTypeDesc,
}

//---------------------------------------------------------------------------//

MaterialTypeRef :: common.Ref(MaterialTypeResource)

//---------------------------------------------------------------------------//

MATERIAL_PROPERTIES_BUFFER_SIZE :: size_of(MaterialProperties) * MAX_MATERIAL_INSTANCES

//---------------------------------------------------------------------------//

InvalidMaterialTypeRef := MaterialTypeRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_TYPE_REF_ARRAY: common.RefArray(MaterialTypeResource)

//---------------------------------------------------------------------------//

MaterialPropertiesFlagBits :: enum u32 {
	HasAlbedoImage,
	HasNormalImage,
	HasRoughnessImage,
	HasMetalnessImage,
	HasOcclusionImage,
}

MaterialPropertiesFlags :: distinct bit_set[MaterialPropertiesFlagBits;u32]

//---------------------------------------------------------------------------//

//16 byte alignment
MaterialProperties :: struct #packed {
	albedo:             glsl.vec3,
	albedo_image_id:    u32,
	normal:             glsl.vec3,
	normal_image_id:    u32,
	roughness:          f32,
	metalness:          f32,
	occlusion:          f32,
	roughness_image_id: u32,
	metalness_image_id: u32,
	occlusion_image_id: u32,
	flags:              MaterialPropertiesFlags,
	_padding:           [4]byte,
}

//---------------------------------------------------------------------------//

material_type_init :: proc() -> bool {


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

	material_types_load_types_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

material_type_deinit :: proc() {
	buffer_destroy(g_renderer_buffers.material_instances_buffer_ref)
}

//---------------------------------------------------------------------------//

material_type_create :: proc(p_material_ref: MaterialTypeRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

material_type_allocate :: proc(p_name: common.Name) -> MaterialTypeRef {
	ref := MaterialTypeRef(
		common.ref_create(MaterialTypeResource, &G_MATERIAL_TYPE_REF_ARRAY, p_name),
	)
	g_resources.material_types[material_type_get_idx(ref)] = {}
	g_resources.material_types[material_type_get_idx(ref)].name = p_name
	return ref
}

//---------------------------------------------------------------------------//

material_type_get_idx :: #force_inline proc(p_ref: MaterialTypeRef) -> u32 {
	return common.ref_get_idx(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_type_destroy :: proc(p_ref: MaterialTypeRef) {
	material_type := &g_resources.material_types[material_type_get_idx(p_ref)]

	if len(material_type.desc.defines) > 0 {
		delete(material_type.desc.defines, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	delete(material_type.desc.material_passes_refs, G_RENDERER_ALLOCATORS.resource_allocator)

	common.ref_free(&G_MATERIAL_TYPE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private = "file")
material_types_load_types_from_config_file :: proc() -> bool {
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
		material_type_ref := material_type_allocate(
			common.create_name(material_type_json_entry.name),
		)

		material_type := &g_resources.material_types[material_type_get_idx(material_type_ref)]
		material_type.name = common.create_name(material_type_json_entry.name)

		// Defines
		material_type.desc.defines = make(
			[]common.Name,
			len(material_type_json_entry.defines),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		for define, i in material_type_json_entry.defines {
			material_type.desc.defines[i] = common.create_name(define)
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

		assert(material_type_create(material_type_ref))
	}

	return true
}

//--------------------------------------------------------------------------//

material_type_find :: proc {
	material_type_find_by_name,
	material_type_find_by_str,
}

material_type_find_by_name :: proc(p_name: common.Name) -> MaterialTypeRef {
	ref := common.ref_find_by_name(&G_MATERIAL_TYPE_REF_ARRAY, p_name)
	if ref == InvalidMaterialTypeRef {
		return InvalidMaterialTypeRef
	}
	return MaterialTypeRef(ref)
}

//--------------------------------------------------------------------------//

material_type_find_by_str :: proc(p_str: string) -> MaterialTypeRef {
	return material_type_find_by_name(common.create_name(p_str))
}

//--------------------------------------------------------------------------//
