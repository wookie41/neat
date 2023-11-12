package engine

//---------------------------------------------------------------------------//

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"
import "core:path/filepath"

import "../common"
import "../renderer"

//---------------------------------------------------------------------------//

@(private = "file")
G_METADATA_FILE_VERSION :: 1

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_DB_PATH :: "app_data/engine/assets/materials/db.json"

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_ASSETS_DIR :: "app_data/engine/assets/materials/"

//---------------------------------------------------------------------------//

@(private = "file")
MAX_MATERIAL_ASSETS :: 2048

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_ASSET_REF_ARRAY: common.RefArray(MaterialAsset)
@(private = "file")
G_MATERIAL_ASSET_ARRAY: []MaterialAsset

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	material_database: AssetDatabase,
}

//---------------------------------------------------------------------------//

@(private)
BaseMaterialProperties :: struct {
	flags: u32,
}

//---------------------------------------------------------------------------//

@(private)
DefaultMaterialPropertiesAssetJSON :: struct {
	using base:           BaseMaterialProperties,
	albedo:               glsl.vec3,
	normal:               glsl.vec3,
	roughness:            f32,
	metalness:            f32,
	occlusion:            f32,
	albedo_image_name:    string `json:"albedoImageName"`,
	normal_image_name:    string `json:"normalImageName"`,
	roughness_image_name: string `json:"normalImageName"`,
	metalness_image_name: string `json:"metalnessImageName"`,
	occlusion_image_name: string `json:"occlusionImageName"`,
}

//---------------------------------------------------------------------------//

MaterialAssetMetadata :: struct {
	using base:         AssetMetadataBase,
	material_type_name: common.Name,
}

//---------------------------------------------------------------------------//

MaterialAsset :: struct {
	using metadata:        MaterialAssetMetadata,
	material_instance_ref: renderer.MaterialInstanceRef,
	flags:                 u32,
	ref_count:             u32,
}

//---------------------------------------------------------------------------//

MaterialAssetRef :: common.Ref(MaterialAsset)

//---------------------------------------------------------------------------//

InvalidMaterialAssetRef := MaterialAssetRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

material_asset_init :: proc() {

	G_MATERIAL_ASSET_REF_ARRAY = common.ref_array_create(
		MaterialAsset,
		MAX_MATERIAL_ASSETS,
		G_ALLOCATORS.asset_allocator,
	)
	G_MATERIAL_ASSET_ARRAY = make(
		[]MaterialAsset,
		MAX_MATERIAL_ASSETS,
		G_ALLOCATORS.asset_allocator,
	)

	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)

	context.temp_allocator = temp_arena.allocator

	asset_database_init(&INTERNAL.material_database, G_MATERIAL_DB_PATH)
	asset_database_read(&INTERNAL.material_database)
}

//---------------------------------------------------------------------------//

allocate_material_asset_ref :: proc(p_name: common.Name) -> MaterialAssetRef {
	ref := MaterialAssetRef(common.ref_create(MaterialAsset, &G_MATERIAL_ASSET_REF_ARRAY, p_name))
	material := material_asset_get(ref)
	material.name = p_name
	material.type = .Material
	return ref
}

//---------------------------------------------------------------------------//

material_asset_get :: proc(p_ref: MaterialAssetRef) -> ^MaterialAsset {
	return &G_MATERIAL_ASSET_ARRAY[common.ref_get_idx(&G_MATERIAL_ASSET_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

material_asset_create :: proc(p_material_asset_ref: MaterialAssetRef) -> bool {
	material_asset := material_asset_get(p_material_asset_ref)

	material_type_ref := renderer.find_material_type(material_asset.material_type_name)
	if material_type_ref == renderer.InvalidMaterialTypeRef {
		log.warn(
			"Failed to create material '%s' - unsupported material type '%s'",
			common.get_string(material_asset.name),
			common.get_string(material_asset.material_type_name),
		)
		return false
	}

	material_type_idx := renderer.get_material_type_idx(material_type_ref)
	material_type := &renderer.g_resources.material_types[material_type_idx]

	// Create a material instance for this material asset
	material_asset.material_instance_ref = renderer.allocate_material_instance_ref(
		material_asset.name,
	)
	material_instance_idx := renderer.get_material_instance_idx(
		material_asset.material_instance_ref,
	)
	material_instance := &renderer.g_resources.material_instances[material_instance_idx]
	material_instance.desc.material_type_ref = material_type_ref

	renderer.create_material_instance(material_asset.material_instance_ref)

	material_asset.ref_count = 1
	material_asset.base = AssetMetadataBase {
		name    = material_asset.name,
		type    = .Material,
		uuid    = uuid_create(),
		version = G_METADATA_FILE_VERSION,
	}

	return true
}

//---------------------------------------------------------------------------//

material_asset_save :: proc(p_ref: MaterialAssetRef) -> bool {
	material_asset := material_asset_get(p_ref)

	material_instance_idx := renderer.get_material_instance_idx(
		material_asset.material_instance_ref,
	)
	material_instance := &renderer.g_resources.material_instances[material_instance_idx]
	material_type_ref := material_instance.desc.material_type_ref
	material_type := &renderer.g_resources.material_types[renderer.get_material_type_idx(material_type_ref)]

	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)

	context.temp_allocator = temp_arena.allocator

	// Write the metadata file
	{
		material_metadata := MaterialAssetMetadata {
			name    = material_asset.name,
			uuid    = material_asset.uuid,
			version = G_METADATA_FILE_VERSION,
			type    = .Material,
		}
		material_metadata_file_path := common.aprintf(
			temp_arena.allocator,
			"%s%s.metadata",
			G_MATERIAL_ASSETS_DIR,
			common.get_string(material_asset.name),
		)

		if common.write_json_file(
			   material_metadata_file_path,
			   MaterialAssetMetadata,
			   material_metadata,
			   temp_arena.allocator,
		   ) ==
		   false {
			log.warnf(
				"Failed to save material '%s' - couldn't save metadata\n",
				common.get_string(material_asset.name),
			)
			return false

		}
	}

	// Write material properties
	material_asset_data: []byte
	marshal_error: json.Marshal_Error

	switch material_type.desc.properties_struct_type {
	case renderer.DefaultMaterialTypeProperties:
		material_asset_data, marshal_error = material_asset_save_properties_default(
			material_asset.material_instance_ref,
			(^renderer.DefaultMaterialTypeProperties)(
				material_instance.material_properties_buffer_ptr,
			),
		)
	case:
		assert(false, "Unsupported material properties type")
	}

	if marshal_error != nil {
		return false
	}
	material_asset_path := filepath.join(
		{G_MATERIAL_ASSETS_DIR, common.get_string(material_asset.name), "json"},
		temp_arena.allocator,
	)
	if os.write_entire_file(material_asset_path, material_asset_data) == false {
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

material_asset_load :: proc(p_name: common.Name) -> MaterialAssetRef {

	// Check if it's already loaded
	loaded_material_asset_ref := common.ref_find_by_name(&G_MATERIAL_ASSET_REF_ARRAY, p_name)
	if loaded_material_asset_ref != InvalidMaterialAssetRef {
		material_asset_get(loaded_material_asset_ref).ref_count += 1
		return loaded_material_asset_ref
	}

	temp_arena: common.TempArena
	common.temp_arena_init(&temp_arena)
	defer common.temp_arena_delete(temp_arena)

	material_name := common.get_string(p_name)

	context.temp_allocator = temp_arena.allocator

	// Load  metadata
	material_metadata: MaterialAssetMetadata
	{
		material_metadata_file_path := common.aprintf(
			temp_arena.allocator,
			"%s%s.metadata",
			G_MATERIAL_ASSETS_DIR,
			material_name,
		)
		material_metadata_json, success := os.read_entire_file(
			material_metadata_file_path,
			temp_arena.allocator,
		)
		if !success {
			log.warnf("Failed to load material '%s' - couldn't load metadata\n", material_name)
			return InvalidMaterialAssetRef
		}
		err := json.unmarshal(
			material_metadata_json,
			&material_metadata,
			.JSON5,
			temp_arena.allocator,
		)
		if err != nil {
			log.warnf("Failed to load material '%s' - couldn't read metadata\n", material_name)
			return InvalidMaterialAssetRef
		}
	}

	material_type_ref := renderer.find_material_type(material_metadata.material_type_name)
	if material_type_ref == renderer.InvalidMaterialTypeRef {
		log.warn(
			"Failed to load material '%s' - unsupported material type '%s'",
			material_name,
			common.get_string(material_metadata.material_type_name),
		)
		return InvalidMaterialAssetRef
	}
	material_type_idx := renderer.get_material_type_idx(material_type_ref)

	material_type := &renderer.g_resources.material_types[material_type_idx]

	material_asset_ref := allocate_material_asset_ref(p_name)
	material_asset := material_asset_get(material_asset_ref)


	// Create a material instance for this material asset
	material_asset.material_instance_ref = renderer.allocate_material_instance_ref(p_name)
	material_instance_idx := renderer.get_material_instance_idx(
		material_asset.material_instance_ref,
	)
	material_instance := &renderer.g_resources.material_instances[material_instance_idx]
	material_instance.desc.material_type_ref = material_type_ref

	renderer.create_material_instance(material_asset.material_instance_ref)

	// Load the material properties
	material_asset_path := filepath.join(
		{G_MATERIAL_ASSETS_DIR, common.get_string(material_asset.name), "json"},
		temp_arena.allocator,
	)
	material_data, success := os.read_entire_file(material_asset_path, temp_arena.allocator)

	if success == false {
		common.ref_free(&G_MATERIAL_ASSET_REF_ARRAY, material_asset_ref)
		renderer.destroy_material_instance(material_asset.material_instance_ref)
		return InvalidMaterialAssetRef
	}

	load_success := false

	switch material_type.desc.properties_struct_type {
	case renderer.DefaultMaterialTypeProperties:
		load_success = material_asset_load_properties_default(
			material_data,
			material_asset.material_instance_ref,
			(^renderer.DefaultMaterialTypeProperties)(
				material_instance.material_properties_buffer_ptr,
			),
		)
	case:
		assert(false, "Unsupported material properties type")
	}

	material_asset.ref_count = 1

	return material_asset_ref
}


//---------------------------------------------------------------------------//

@(private = "file")
material_asset_save_properties_default :: proc(
	p_material_instance_ref: renderer.MaterialInstanceRef,
	p_material_properties: ^renderer.DefaultMaterialTypeProperties,
) -> (
	[]byte,
	json.Marshal_Error,
) {

	props_json := DefaultMaterialPropertiesAssetJSON {
		flags     = renderer.material_instance_get_flags(p_material_instance_ref),
		albedo    = p_material_properties.albedo,
		normal    = p_material_properties.normal,
		roughness = p_material_properties.roughness,
		metalness = p_material_properties.metalness,
		occlusion = p_material_properties.occlusion,
	}

	if (renderer.material_instance_get_flag(p_material_instance_ref, "HasAlbedoImage")) {
		props_json.albedo_image_name = common.get_string(
			renderer.g_resources.images[p_material_properties.albedo_image_id].desc.name,
		)
	}

	if (renderer.material_instance_get_flag(p_material_instance_ref, "HasNormalImage")) {
		props_json.normal_image_name = common.get_string(
			renderer.g_resources.images[p_material_properties.normal_image_id].desc.name,
		)
	}

	if (renderer.material_instance_get_flag(p_material_instance_ref, "HasRoughnessImage")) {
		props_json.roughness_image_name = common.get_string(
			renderer.g_resources.images[p_material_properties.roughness_image_id].desc.name,
		)
	}

	if (renderer.material_instance_get_flag(p_material_instance_ref, "HasMetalnessImage")) {
		props_json.metalness_image_name = common.get_string(
			renderer.g_resources.images[p_material_properties.metalness_image_id].desc.name,
		)
	}

	if (renderer.material_instance_get_flag(p_material_instance_ref, "HasOcclusionImage")) {
		props_json.occlusion_image_name = common.get_string(
			renderer.g_resources.images[p_material_properties.occlusion_image_id].desc.name,
		)
	}

	return json.marshal(
		props_json,
		json.Marshal_Options{spec = .JSON5, pretty = true},
		context.temp_allocator,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
material_asset_load_properties_default :: proc(
	p_material_properties_data: []byte,
	p_material_instance_ref: renderer.MaterialInstanceRef,
	p_material_properties: ^renderer.DefaultMaterialTypeProperties,
) -> bool {

	material_props: DefaultMaterialPropertiesAssetJSON

	error := json.unmarshal(
		p_material_properties_data,
		&material_props,
		.JSON5,
		context.temp_allocator,
	)
	if error != nil {
		return false
	}

	renderer.material_instance_set_flags(p_material_instance_ref, material_props.flags)

	p_material_properties.albedo = material_props.albedo
	p_material_properties.normal = material_props.normal
	p_material_properties.roughness = material_props.roughness
	p_material_properties.metalness = material_props.metalness
	p_material_properties.occlusion = material_props.occlusion

	if renderer.material_instance_get_flag(p_material_instance_ref, "HasAlbedoImage") {
		material_asset_set_image_by_name(
			&p_material_properties.albedo_image_id,
			material_props.albedo_image_name,
		)
	}
	if renderer.material_instance_get_flag(p_material_instance_ref, "HasNormalImage") {
		material_asset_set_image_by_name(
			&p_material_properties.normal_image_id,
			material_props.normal_image_name,
		)
	}
	if renderer.material_instance_get_flag(p_material_instance_ref, "HasRoughnessImage") {
		material_asset_set_image_by_name(
			&p_material_properties.roughness_image_id,
			material_props.roughness_image_name,
		)
	}
	if renderer.material_instance_get_flag(p_material_instance_ref, "HasMetalnessImage") {
		material_asset_set_image_by_name(
			&p_material_properties.metalness_image_id,
			material_props.metalness_image_name,
		)
	}
	if renderer.material_instance_get_flag(p_material_instance_ref, "HasOcclusionImage") {
		material_asset_set_image_by_name(
			&p_material_properties.occlusion_image_id,
			material_props.occlusion_image_name,
		)
	}

	return true
}

//---------------------------------------------------------------------------//

material_asset_save_new_default :: proc(
	p_material_asset_ref: MaterialAssetRef,
	p_material_properties: DefaultMaterialPropertiesAssetJSON,
) -> bool {

	material_asset := material_asset_get(p_material_asset_ref)

	material_asset_path := filepath.join(
		{G_MATERIAL_ASSETS_DIR, common.get_string(material_asset.name), "json"},
		context.temp_allocator,
	)

	return common.write_json_file(
		material_asset_path,
		DefaultMaterialPropertiesAssetJSON,
		p_material_properties,
		context.temp_allocator,
	)
}

//---------------------------------------------------------------------------//

@(private = "file")
material_asset_set_image_by_name :: proc(p_image_id: ^u32, p_image_name: string) {
	image_ref := renderer.find_image(p_image_name)
	if image_ref != renderer.InvalidImageRef {
		p_image_id^ = renderer.g_resources.images[renderer.get_image_idx(image_ref)].bindless_idx
	}
}

//---------------------------------------------------------------------------//

material_asset_unload :: proc(p_material_asset_ref: MaterialAssetRef) {
	material_asset := material_asset_get(p_material_asset_ref)
	material_asset.ref_count -= 1
	if material_asset.ref_count > 0 {
		return
	}

	renderer.destroy_material_instance(material_asset.material_instance_ref)
	common.ref_free(&G_MATERIAL_ASSET_REF_ARRAY, p_material_asset_ref)
}

//---------------------------------------------------------------------------//
