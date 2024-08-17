package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"
import "core:slice"
import "core:strings"

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
	name:                 common.Name,
	defines:              []common.Name,
	material_passes_refs: []MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialTypeResource :: struct {
	desc: MaterialTypeDesc,
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

@(private)
g_material_pass_bind_group_layout_ref: BindGroupLayoutRef

//---------------------------------------------------------------------------//

init_material_types :: proc() -> bool {

	// Create a bind group layout for material passes
	{
		g_material_pass_bind_group_layout_ref = allocate_bind_group_layout_ref(
			common.create_name("MaterialPasses"),
			1,
		)

		bind_group_layout := &g_resources.bind_group_layouts[get_bind_group_layout_idx(g_material_pass_bind_group_layout_ref)]

		// Instance info data
		bind_group_layout.desc.bindings[0] = {
			count         = 1,
			shader_stages = {.Vertex, .Fragment, .Compute},
			type          = .StorageBufferDynamic,
		}

		create_bind_group_layout(g_material_pass_bind_group_layout_ref) or_return
	}

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

	load_material_types_from_config_file() or_return

	return true
}

//---------------------------------------------------------------------------//

deinit_material_types :: proc() {
	destroy_buffer(g_renderer_buffers.material_instances_buffer_ref)
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

	material_type_defines := make([]string, len(material_type.desc.defines), temp_arena.allocator)
	for define, i in material_type.desc.defines {
		material_type_defines[i] = common.get_string(define)
	}

	// Compile the shaders for each material pass that uses this material
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

		assert(material_pass.vertex_shader_ref == InvalidShaderRef)
		assert(material_pass.fragment_shader_ref == InvalidShaderRef)

		material_pass.vertex_shader_ref = allocate_shader_ref(common.create_name(vert_shader_path))
		material_pass.fragment_shader_ref = allocate_shader_ref(common.create_name(frag_shader_path))

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
		material_pass.pipeline_ref = graphics_pipeline_allocate_ref(material_pass.desc.name, 4, 0)
		pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(material_pass.pipeline_ref)]
		pipeline.desc.bind_group_layout_refs = {
			g_material_pass_bind_group_layout_ref,
			G_RENDERER.uniforms_bind_group_layout_ref,
			G_RENDERER.globals_bind_group_layout_ref,
			G_RENDERER.bindless_bind_group_layout_ref,
		}

		pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
		pipeline.desc.vert_shader_ref = material_pass.vertex_shader_ref
		pipeline.desc.frag_shader_ref = material_pass.fragment_shader_ref
		pipeline.desc.vertex_layout = .Mesh

		success = graphics_pipeline_create(material_pass.pipeline_ref)
		assert(success)
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

	if len(material_type.desc.defines) > 0 {
		delete(material_type.desc.defines, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	delete(material_type.desc.material_passes_refs, G_RENDERER_ALLOCATORS.resource_allocator)

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

		assert(create_material_type(material_type_ref))
	}

	return true
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
