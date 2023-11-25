
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:encoding/json"
import "core:log"
import "core:os"
import "core:slice"

//---------------------------------------------------------------------------//

MaterialPassDesc :: struct {
	name:                     common.Name,
	vertex_shader_path:       common.Name,
	fragment_shader_path:     common.Name,
	render_pass_ref:          RenderPassRef,
	additional_feature_names: []string,
}

//---------------------------------------------------------------------------//

MaterialPassResource :: struct {
	desc:                MaterialPassDesc,
	vertex_shader_ref:   ShaderRef,
	fragment_shader_ref: ShaderRef,
	pipeline_ref:        PipelineRef,
}

//---------------------------------------------------------------------------//

MaterialPassRef :: common.Ref(MaterialPassResource)

//---------------------------------------------------------------------------//

InvalidMaterialPassRef := MaterialPassRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_REF_ARRAY: common.RefArray(MaterialPassResource)
@(private = "file")
G_MATERIAL_PASS_RESOURCE_ARRAY: []MaterialPassResource

//---------------------------------------------------------------------------//

MaterialPassJSONEntry :: struct {
	name:                     string,
	vertex_shader_path:       string `json:"vertexShaderPath"`,
	fragment_shader_path:     string `json:"fragmentShaderPath"`,
	render_pass_name:         string `json:"renderPass"`,
	additional_feature_names: []string `json:"additionalFeatureNames"`,
}

//---------------------------------------------------------------------------//


init_material_passs :: proc() -> bool {
	G_MATERIAL_PASS_REF_ARRAY = common.ref_array_create(
		MaterialPassResource,
		MAX_MATERIAL_PASSES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MATERIAL_PASS_RESOURCE_ARRAY = make(
		[]MaterialPassResource,
		MAX_MATERIAL_PASSES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	load_material_passes_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_passs :: proc() {
}

//---------------------------------------------------------------------------//

create_material_pass :: proc(p_material_pass_ref: MaterialPassRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

allocate_material_pass_ref :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := MaterialPassRef(
		common.ref_create(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_name),
	)
	get_material_pass(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_pass :: proc(p_ref: MaterialPassRef) -> ^MaterialPassResource {
	return &G_MATERIAL_PASS_RESOURCE_ARRAY[common.ref_get_idx(&G_MATERIAL_PASS_REF_ARRAY, p_ref)]
}

//--------------------------------------------------------------------------//

destroy_material_pass :: proc(p_ref: MaterialPassRef) {
	material_pass := get_material_pass(p_ref)
	if len(material_pass.desc.additional_feature_names) > 0 {
		delete(
			material_pass.desc.additional_feature_names,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	destroy_shader(material_pass.vertex_shader_ref)
	destroy_shader(material_pass.fragment_shader_ref)
	common.ref_free(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

load_material_passes_from_config_file :: proc() -> bool {
	temp_arena : common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	material_passes_config := "app_data/renderer/config/material_passes.json"
	material_passes_json_data, file_read_ok := os.read_entire_file(
		material_passes_config,
		temp_arena.allocator,
	)

	if file_read_ok == false {
		return false
	}

	// Parse the material passes config file
	material_passes_json_entries: []MaterialPassJSONEntry

	if err := json.unmarshal(
		material_passes_json_data,
		&material_passes_json_entries,
		.JSON5,
		temp_arena.allocator,
	); err != nil {
		log.errorf("Failed to read material passess json: %s\n", err)
		return false
	}

	for entry in material_passes_json_entries {
		material_pass_ref := allocate_material_pass_ref(common.create_name(entry.name))
		material_pass := get_material_pass(material_pass_ref)

		material_pass.desc.vertex_shader_path = common.create_name(entry.vertex_shader_path)
		material_pass.desc.fragment_shader_path = common.create_name(entry.fragment_shader_path)

		material_pass.desc.render_pass_ref = find_render_pass_by_name(entry.render_pass_name)
		assert(material_pass.desc.render_pass_ref != InvalidRenderPassRef)

		if len(entry.additional_feature_names) > 0 {
			material_pass.desc.additional_feature_names = slice.clone(
				entry.additional_feature_names,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		create_material_pass(material_pass_ref)
	}

	return true
}

//--------------------------------------------------------------------------//

@(private)
find_material_pass_by_name :: proc {
	find_material_pass_by_name_name,
	find_material_pass_by_name_str,
}

//--------------------------------------------------------------------------//

@(private)
find_material_pass_by_name_name :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := common.ref_find_by_name(&G_MATERIAL_PASS_REF_ARRAY, p_name)
	if ref == InvalidMaterialPassRef {
		return InvalidMaterialPassRef
	}
	return MaterialPassRef(ref)
}

//--------------------------------------------------------------------------//

@(private)
find_material_pass_by_name_str :: proc(p_name: string) -> MaterialPassRef {
	ref := common.ref_find_by_name(&G_MATERIAL_PASS_REF_ARRAY, common.create_name(p_name))
	if ref == InvalidMaterialPassRef {
		return InvalidMaterialPassRef
	}
	return MaterialPassRef(ref)
}

//--------------------------------------------------------------------------//
