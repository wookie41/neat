#+feature dynamic-literals

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
	include_path: common.Name,
	defines:      []string,
}

//---------------------------------------------------------------------------//

MaterialPassResource :: struct {
	name:                    common.Name,
	desc:                    MaterialPassDesc,
	pass_type_pipeline_refs: []GraphicsPipelineRef,
}

//---------------------------------------------------------------------------//

MaterialPassType :: enum u8 {
	GBuffer,
	CascadeShadows,
}

//---------------------------------------------------------------------------//

MaterialPassRef :: common.Ref(MaterialPassResource)

//---------------------------------------------------------------------------//

InvalidMaterialPassRef := MaterialPassRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

MaterialPassJSONEntry :: struct {
	name:         string,
	include_path: string `json:"includePath"`,
	defines:      []string `json:"defines"`,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_REF_ARRAY: common.RefArray(MaterialPassResource)

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_TYPE_MAPPING := map[string]MaterialPassType {
	"GBuffer"        = .GBuffer,
	"CascadeShadows" = .CascadeShadows,
}
//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_TYPE_SHADERS_MAPPING := map[MaterialPassType]string {
	.GBuffer        = "material_pass_gbuffer.hlsl",
	.CascadeShadows = "material_pass_cascade_shadows.hlsl",
}

//---------------------------------------------------------------------------//

material_pass_init :: proc() -> bool {
	G_MATERIAL_PASS_REF_ARRAY = common.ref_array_create(
		MaterialPassResource,
		MAX_MATERIAL_PASSES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.material_passes = make_soa(
		#soa[]MaterialPassResource,
		MAX_MATERIAL_PASSES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	material_pass_load_passes_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

material_pass_deinit :: proc() {
}

//---------------------------------------------------------------------------//

material_pass_create :: proc(p_material_pass_ref: MaterialPassRef) -> bool {
	material_pass := &g_resources.material_passes[material_pass_get_idx(p_material_pass_ref)]
	material_pass.pass_type_pipeline_refs = make(
		[]GraphicsPipelineRef,
		len(MaterialPassType),
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	for i in 0 ..< len(MaterialPassType) {
		material_pass.pass_type_pipeline_refs[i] = InvalidGraphicsPipelineRef
	}

	return true
}

//---------------------------------------------------------------------------//

material_pass_allocate :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := MaterialPassRef(
		common.ref_create(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_name),
	)
	g_resources.material_passes[material_pass_get_idx(ref)] = {}
	g_resources.material_passes[material_pass_get_idx(ref)].name = p_name
	return ref
}
//---------------------------------------------------------------------------//

material_pass_get_idx :: proc(p_ref: MaterialPassRef) -> u32 {
	return common.ref_get_idx(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_pass_destroy :: proc(p_ref: MaterialPassRef) {
	material_pass := &g_resources.material_passes[material_pass_get_idx(p_ref)]
	if len(material_pass.desc.defines) > 0 {
		delete(material_pass.desc.defines, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	delete(material_pass.pass_type_pipeline_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	common.ref_free(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private = "file")
material_pass_load_passes_from_config_file :: proc() -> bool {
	temp_arena: common.Arena
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
		material_pass_ref := material_pass_allocate(common.create_name(entry.name))
		material_pass := &g_resources.material_passes[material_pass_get_idx(material_pass_ref)]

		material_pass.desc.include_path = common.create_name(entry.include_path)

		if len(entry.defines) > 0 {
			material_pass.desc.defines = slice.clone(
				entry.defines,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		material_pass_create(material_pass_ref)
	}

	return true
}

//--------------------------------------------------------------------------//

@(private)
find_material_pass_by_name :: proc {
	material_pass_find_by_name_name,
	material_pass_find_by_name_str,
}

//--------------------------------------------------------------------------//

@(private)
material_pass_find_by_name_name :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := common.ref_find_by_name(&G_MATERIAL_PASS_REF_ARRAY, p_name)
	if ref == InvalidMaterialPassRef {
		return InvalidMaterialPassRef
	}
	return MaterialPassRef(ref)
}

//--------------------------------------------------------------------------//

@(private)
material_pass_find_by_name_str :: proc(p_name: string) -> MaterialPassRef {
	ref := common.ref_find_by_name(&G_MATERIAL_PASS_REF_ARRAY, common.create_name(p_name))
	if ref == InvalidMaterialPassRef {
		return InvalidMaterialPassRef
	}
	return MaterialPassRef(ref)
}

//--------------------------------------------------------------------------//

material_pass_compile_for_type :: proc(
	p_material_pass_ref: MaterialPassRef,
	p_material_pass_type: MaterialPassType,
	p_render_pass_ref: RenderPassRef,
	p_bind_group_layout_ref: BindGroupLayoutRef,
) -> (
	result: bool,
) {

	pass_type_idx := transmute(u8)p_material_pass_type
	material_pass := &g_resources.material_passes[material_pass_get_idx(p_material_pass_ref)]

	if material_pass.pass_type_pipeline_refs[pass_type_idx] != InvalidGraphicsPipelineRef {
		return
	}

	// Inject the material pass include
	include_path := common.get_string(material_pass.desc.include_path)

	material_pass_type_include_def := common.aprintf(
		G_RENDERER_ALLOCATORS.resource_allocator,
		"MATERIAL_PASS_INCLUDE=\\\"%s\\\"",
		include_path,
	)

	shader_defines, _ := slice.concatenate(
		[][]string{{material_pass_type_include_def}, material_pass.desc.defines},
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	defer if result == false {
		delete(shader_defines, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(material_pass_type_include_def, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	assert(p_material_pass_type in G_MATERIAL_PASS_TYPE_SHADERS_MAPPING)

	shader_path := common.create_name(G_MATERIAL_PASS_TYPE_SHADERS_MAPPING[p_material_pass_type])
	vertex_shader_ref := shader_allocate(shader_path)
	pixel_shader_ref := shader_allocate(shader_path)

	vertex_shader := &g_resources.shaders[shader_get_idx(vertex_shader_ref)]
	pixel_shader := &g_resources.shaders[shader_get_idx(pixel_shader_ref)]

	vertex_shader.desc.features = shader_defines
	vertex_shader.desc.file_path = shader_path
	vertex_shader.desc.stage = .Vertex

	pixel_shader.desc.features = shader_defines
	pixel_shader.desc.file_path = shader_path
	pixel_shader.desc.stage = .Pixel

	shader_create(vertex_shader_ref) or_return
	defer if result == false {
		shader_destroy(vertex_shader_ref)
	}

	shader_create(pixel_shader_ref) or_return
	defer if result == false {
		shader_destroy(pixel_shader_ref)
	}

	pipeline_ref := graphics_pipeline_allocate(material_pass.name, 4, 0)
	pipeline := &g_resources.graphics_pipelines[graphics_pipeline_get_idx(pipeline_ref)]
	pipeline.desc.bind_group_layout_refs = {
		p_bind_group_layout_ref,
		G_RENDERER.uniforms_bind_group_layout_ref,
		G_RENDERER.globals_bind_group_layout_ref,
		G_RENDERER.bindless_bind_group_layout_ref,
	}

	pipeline.desc.render_pass_ref = p_render_pass_ref
	pipeline.desc.vert_shader_ref = vertex_shader_ref
	pipeline.desc.frag_shader_ref = pixel_shader_ref
	pipeline.desc.vertex_layout = .Mesh

	graphics_pipeline_create(pipeline_ref) or_return

	material_pass.pass_type_pipeline_refs[pass_type_idx] = pipeline_ref

	return true
}

//---------------------------------------------------------------------------//

@(private)
material_pass_parse_type :: proc(p_name: string) -> (MaterialPassType, bool) {

	if p_name in G_MATERIAL_PASS_TYPE_MAPPING {
		return G_MATERIAL_PASS_TYPE_MAPPING[p_name], true
	}

	return nil, false
}

//---------------------------------------------------------------------------//
