
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:os"
import "core:encoding/json"
import "core:log"

//---------------------------------------------------------------------------//

MaterialPassDesc :: struct {
	name:                     common.Name,
	base_vertex_shader_ref:   ShaderRef,
	base_fragment_shader_ref: ShaderRef,
	render_pass_ref:          RenderPassRef,
}

//---------------------------------------------------------------------------//

MaterialPassResource :: struct {
	desc: MaterialPassDesc,
}

//---------------------------------------------------------------------------//

MaterialPassRef :: common.Ref(MaterialPassResource)

//---------------------------------------------------------------------------//

InvalidMaterialPassRef := MaterialPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_REF_ARRAY: common.RefArray(MaterialPassResource)
@(private = "file")
G_MATERIAL_PASS_RESOURCE_ARRAY: []MaterialPassResource

//---------------------------------------------------------------------------//

MaterialPassJSONEntry :: struct {
	name:                      string,
	base_vertex_shader_name:   string `json:"baseVertexShader"`,
	base_fragment_shader_name: string `json:"baseFragmentShader"`,
	render_pass_name:          string `json:"renderPass"`,
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
	// material_pass := get_material_pass(p_ref)
	common.ref_free(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

load_material_passes_from_config_file :: proc() -> bool {
	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	material_passes_config := "app_data/renderer/config/material_passes.json"
	material_passes_json_data, file_read_ok := os.read_entire_file(
		material_passes_config,
	)

	if file_read_ok == false {
		return false
	}

	// Parse the material passes config file
	material_passes_json_entries: []MaterialPassJSONEntry

	if err := json.unmarshal(material_passes_json_data, &material_passes_json_entries);
	   err != nil {
		log.errorf("Failed to read material passess json: %s\n", err)
		return false
	}

	for entry in material_passes_json_entries {
		material_pass_ref := allocate_material_pass_ref(common.create_name(entry.name))
		material_pass := get_material_pass(material_pass_ref)

		material_pass.desc.base_vertex_shader_ref = find_shader_by_name(
			entry.base_vertex_shader_name,
		)
		assert(material_pass.desc.base_vertex_shader_ref != InvalidShaderRef)

		material_pass.desc.base_fragment_shader_ref = find_shader_by_name(
			entry.base_fragment_shader_name,
		)
		assert(material_pass.desc.base_fragment_shader_ref != InvalidShaderRef)

		material_pass.desc.render_pass_ref = find_render_pass_by_name(entry.render_pass_name)
		assert(material_pass.desc.render_pass_ref != InvalidRenderPassRef)

		create_material_pass(material_pass_ref)
	}

	return true
}

//--------------------------------------------------------------------------//

@(private)
find_material_pass_by_name :: proc {find_material_pass_by_name_name, find_material_pass_by_name_str}

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
	ref := common.ref_find_by_name(&G_MATERIAL_PASS_REF_ARRAY, common.make_name(p_name))
	if ref == InvalidMaterialPassRef {
		return InvalidMaterialPassRef
	}
	return MaterialPassRef(ref)
}

//--------------------------------------------------------------------------//
