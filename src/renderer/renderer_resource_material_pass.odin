
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
	pixel_shader_path:        common.Name,
	render_pass_ref:          RenderPassRef,
	additional_feature_names: []string,
}

//---------------------------------------------------------------------------//

MaterialPassResource :: struct {
	desc:                   MaterialPassDesc,
	geometry_pipeline_refs: []GraphicsPipelineRef,
}

//---------------------------------------------------------------------------//

GeometryPassType :: enum u8 {
	GBuffer,
	Shadows,
}

//---------------------------------------------------------------------------//

GeometryPassDescription :: struct {
	pass_type:             GeometryPassType,
	bind_group_layout_ref: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

MaterialPassRef :: common.Ref(MaterialPassResource)

//---------------------------------------------------------------------------//

InvalidMaterialPassRef := MaterialPassRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

MaterialPassJSONEntry :: struct {
	name:                     string,
	vertex_shader_path:       string `json:"vertexShaderPath"`,
	pixel_shader_path:        string `json:"pixelShaderPath"`,
	render_pass_name:         string `json:"renderPass"`,
	additional_feature_names: []string `json:"additionalFeatureNames"`,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_PASS_REF_ARRAY: common.RefArray(MaterialPassResource)

//---------------------------------------------------------------------------//

@(private="file")
G_GEOMETRY_PASS_TYPE_MAPPING := map[string]GeometryPassType {
	"GBuffer" = .GBuffer,
	"Shadows" = .Shadows,
}
//---------------------------------------------------------------------------//

@(private="file")
G_GEOMETRY_PASS_SHADERS_MAPPING := map[GeometryPassType]string {
	.GBuffer = "geometry_pass_gbuffer.hlsl",
	.Shadows = "geometry_pass_shadows.hlsl",
}

//---------------------------------------------------------------------------//

init_material_passs :: proc() -> bool {
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
	load_material_passes_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_passs :: proc() {
}

//---------------------------------------------------------------------------//

create_material_pass :: proc(p_material_pass_ref: MaterialPassRef) -> bool {
	material_pass := &g_resources.material_passes[get_material_pass_idx(p_material_pass_ref)]
	material_pass.geometry_pipeline_refs = make(
		[]GraphicsPipelineRef,
		len(GeometryPassType),
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	for i in 0 ..< len(GeometryPassType) {
		material_pass.geometry_pipeline_refs[i] = InvalidGraphicsPipelineRef
	}

	return true
}

//---------------------------------------------------------------------------//

allocate_material_pass_ref :: proc(p_name: common.Name) -> MaterialPassRef {
	ref := MaterialPassRef(
		common.ref_create(MaterialPassResource, &G_MATERIAL_PASS_REF_ARRAY, p_name),
	)
	g_resources.material_passes[get_material_pass_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_pass_idx :: proc(p_ref: MaterialPassRef) -> u32 {
	return common.ref_get_idx(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material_pass :: proc(p_ref: MaterialPassRef) {
	material_pass := &g_resources.material_passes[get_material_pass_idx(p_ref)]
	if len(material_pass.desc.additional_feature_names) > 0 {
		delete(
			material_pass.desc.additional_feature_names,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	delete(material_pass.geometry_pipeline_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	common.ref_free(&G_MATERIAL_PASS_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

load_material_passes_from_config_file :: proc() -> bool {
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
		material_pass_ref := allocate_material_pass_ref(common.create_name(entry.name))
		material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]

		material_pass.desc.vertex_shader_path = common.create_name(entry.vertex_shader_path)
		material_pass.desc.pixel_shader_path = common.create_name(entry.pixel_shader_path)

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

material_pass_compile_geometry_pso :: proc(
	p_material_pass_ref: MaterialPassRef,
	p_geometry_pass_description: GeometryPassDescription,
) -> (
	result: bool,
) {

	geo_pass_idx := transmute(u8)p_geometry_pass_description.pass_type
	material_pass := &g_resources.material_passes[get_material_pass_idx(p_material_pass_ref)]

	if material_pass.geometry_pipeline_refs[geo_pass_idx] != InvalidGraphicsPipelineRef {
		return
	}

	// Inject the material pass includes 
	material_pass_vertex_shader_path := common.get_string(material_pass.desc.vertex_shader_path)
	material_pass_pixel_shader_path := common.get_string(material_pass.desc.pixel_shader_path)

	material_pass_vertex_include_def := common.aprintf(
		G_RENDERER_ALLOCATORS.resource_allocator,
		"MATERIAL_PASS_VERTEX_H=\\\"%s\\\"",
		material_pass_vertex_shader_path,
	)
	material_pass_pixel_include_def := common.aprintf(
		G_RENDERER_ALLOCATORS.resource_allocator,
		"MATERIAL_PASS_PIXEL_H=\\\"%s\\\"",
		material_pass_pixel_shader_path,
	)

	shader_defines, _ := slice.concatenate(
		[][]string {
			{material_pass_vertex_include_def, material_pass_pixel_include_def},
			material_pass.desc.additional_feature_names,
		},
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	defer if result == false {
		delete(shader_defines, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(material_pass_vertex_include_def, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(material_pass_pixel_include_def, G_RENDERER_ALLOCATORS.resource_allocator)
	}


	assert(p_geometry_pass_description.pass_type in G_GEOMETRY_PASS_SHADERS_MAPPING)

	shader_path := common.create_name(G_GEOMETRY_PASS_SHADERS_MAPPING[p_geometry_pass_description.pass_type])
	vertex_shader_ref := allocate_shader_ref(shader_path)
	pixel_shader_ref := allocate_shader_ref(shader_path)

	vertex_shader := &g_resources.shaders[get_shader_idx(vertex_shader_ref)]
	pixel_shader := &g_resources.shaders[get_shader_idx(pixel_shader_ref)]

	vertex_shader.desc.features = shader_defines
	vertex_shader.desc.file_path = shader_path
	vertex_shader.desc.stage = .Vertex

	pixel_shader.desc.features = shader_defines
	pixel_shader.desc.file_path = shader_path
	pixel_shader.desc.stage = .Pixel

	create_shader(vertex_shader_ref) or_return
	defer if result == false {
		destroy_shader(vertex_shader_ref)
	}

	create_shader(pixel_shader_ref) or_return
	defer if result == false {
		destroy_shader(pixel_shader_ref)
	}

	pipeline_ref := graphics_pipeline_allocate_ref(material_pass.desc.name, 4, 0)
	pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(pipeline_ref)]
	pipeline.desc.bind_group_layout_refs = {
		p_geometry_pass_description.bind_group_layout_ref,
		G_RENDERER.uniforms_bind_group_layout_ref,
		G_RENDERER.globals_bind_group_layout_ref,
		G_RENDERER.bindless_bind_group_layout_ref,
	}

	pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
	pipeline.desc.vert_shader_ref = vertex_shader_ref
	pipeline.desc.frag_shader_ref = pixel_shader_ref
	pipeline.desc.vertex_layout = .Mesh

	graphics_pipeline_create(pipeline_ref) or_return

	material_pass.geometry_pipeline_refs[geo_pass_idx] = pipeline_ref

	return true
}

//---------------------------------------------------------------------------//

@(private)
geometry_pass_parse_type :: proc(p_name: string) -> (GeometryPassType, bool) {

	if p_name in G_GEOMETRY_PASS_TYPE_MAPPING {
		return G_GEOMETRY_PASS_TYPE_MAPPING[p_name], true
	}

	return nil, false
}

//---------------------------------------------------------------------------//
