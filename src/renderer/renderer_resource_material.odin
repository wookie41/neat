
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:encoding/json"
import "core:os"
import "core:log"
import "core:mem"

//---------------------------------------------------------------------------//

MATERIAL_PARAMS_BUFFER_SIZE :: 8 * common.MEGABYTE
INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT :: 64

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL : struct {
	material_params_buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

MaterialParam :: struct {
	name:           common.Name,
	num_components: u8,
}

//---------------------------------------------------------------------------//

MaterialTextureParam :: struct {
	name: common.Name,
	image_type: ImageType,
	binding_slot: u32,
}
//---------------------------------------------------------------------------//


MaterialDesc :: struct {
	name:                       common.Name,
	additional_shader_features: []string,
	int_params:                 []MaterialParam,
	float_params:               []MaterialParam,
	texture_params:				[]MaterialTextureParam,
	material_pass_ref: 			MaterialPassRef,
}

//---------------------------------------------------------------------------//

MaterialParamJSONEntry :: struct {
	name: 			string,
	num_components: int		`json:"numComponents"`,
}

//---------------------------------------------------------------------------//

MaterialTextureBindingJSONEntry :: struct {
	name: 	string,
	type: 	string,
}

//---------------------------------------------------------------------------//


MaterialJSONEntry :: struct {
	name: string,
	int_params:					[]MaterialParamJSONEntry 			`json:"int_params"`,
	float_params: 				[]MaterialParamJSONEntry 			`json:"float_param"`,
	texture_params: 			[]MaterialTextureBindingJSONEntry 	`json:"textureParams"`,
	additional_shader_features: []string 							`json:"additionalShaderFeatures"`,
	material_pass_name: string 										`json:"materialPass"`,
}

//---------------------------------------------------------------------------//

MaterialResource :: struct {
	desc:         	MaterialDesc,
	params_buffer: 	BufferSuballocation,
	material_buffer_entry_size_in_bytes: u32,
	// Offset at which float params start for this material in the material buffer
	float_params_offset: u32,
	pipeline_ref: PipelineRef,
	// Next free index in the material buffer to use when creating a new material instnace
	next_material_instance_idx: u32,
	max_material_instance_entries: u32,
	free_material_instance_indices: [dynamic]u32,
}

//---------------------------------------------------------------------------//

MaterialRef :: Ref(MaterialResource)

//---------------------------------------------------------------------------//

InvalidMaterialRef := MaterialRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_REF_ARRAY: RefArray(MaterialResource)

//---------------------------------------------------------------------------//

init_materials :: proc() -> bool {
	G_MATERIAL_REF_ARRAY = create_ref_array(MaterialResource, MAX_MATERIALS)


	INTERNAL.material_params_buffer_ref = allocate_buffer_ref(
		common.create_name("MaterialParamsBuffer")
	)

	material_params_buffer := get_buffer(INTERNAL.material_params_buffer_ref)

	material_params_buffer.desc.flags = {.Mapped, .HostWrite}
	material_params_buffer.desc.size = MATERIAL_PARAMS_BUFFER_SIZE
	material_params_buffer.desc.usage = {.DynamicUniformBuffer}

	create_buffer(INTERNAL.material_params_buffer_ref) or_return

	load_materials_from_config_file() or_return

	return true
}	

//---------------------------------------------------------------------------//

deinit_materials :: proc() {
	destroy_buffer(INTERNAL.material_params_buffer_ref)
}

//---------------------------------------------------------------------------//

create_material :: proc(p_material_ref: MaterialRef) -> (result: bool) {
	material := get_material(p_material_ref)

	material.next_material_instance_idx = 0
	material.max_material_instance_entries = INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT
	material.free_material_instance_indices = make(
		[dynamic]u32, 
		G_RENDERER_ALLOCATORS.resource_allocator)

	allocate_material_params_buffer(material)

	material_pass := get_material_pass(material.desc.material_pass_ref)

	vertex_shader_ref := material_pass.desc.base_vertex_shader_ref
	fragment_shader_ref := material_pass.desc.base_fragment_shader_ref

	has_custom_shaders := false
	// Create a new shader permutation if the material has additional features
	if len(material.desc.additional_shader_features) > 0 {

		has_custom_shaders = true

		vertex_shader_ref = create_shader_permutation(
			material.desc.name,
			material_pass.desc.base_vertex_shader_ref, 
			material.desc.additional_shader_features, 
			true,
		)

		fragment_shader_ref = create_shader_permutation(
			material.desc.name,
			material_pass.desc.base_fragment_shader_ref, 
			material.desc.additional_shader_features, 
			true,
		)
	}

	defer if result == false && has_custom_shaders{
		destroy_shader(vertex_shader_ref)
		destroy_shader(fragment_shader_ref)
	}

	// Create a pipeline for this material
	material.pipeline_ref = allocate_pipeline_ref(material.desc.name)
	defer if result == false {
		destroy_pipeline(material.pipeline_ref)
	}

	pipeline := get_pipeline(material.pipeline_ref)
	pipeline.desc.vert_shader = vertex_shader_ref
	pipeline.desc.frag_shader = fragment_shader_ref
	pipeline.desc.render_pass_ref = material_pass.desc.render_pass_ref
	pipeline.desc.vertex_layout = .Mesh

	assert(create_graphics_pipeline(material.pipeline_ref))

	return true
}

//---------------------------------------------------------------------------//

allocate_material_ref :: proc(p_name: common.Name) -> MaterialRef {
	ref := MaterialRef(create_ref(MaterialResource, &G_MATERIAL_REF_ARRAY, p_name))
	get_material(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

get_material :: proc(p_ref: MaterialRef) -> ^MaterialResource {
	return get_resource(MaterialResource, &G_MATERIAL_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material :: proc(p_ref: MaterialRef) {
	material := get_material(p_ref)

	delete(material.free_material_instance_indices)

	if len(material.desc.int_params) > 0 {
		delete(material.desc.int_params, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	if len(material.desc.float_params) > 0 {
		delete(material.desc.float_params, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	if len(material.desc.texture_params) > 0 {
		delete(material.desc.texture_params, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	if len(material.desc.additional_shader_features) > 0 {
		for feature in material.desc.additional_shader_features {
			delete(feature, G_RENDERER_ALLOCATORS.resource_allocator)
		}
		delete(
			material.desc.additional_shader_features,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)	
	}
	free_ref(MaterialResource, &G_MATERIAL_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

@(private="file")
load_materials_from_config_file :: proc() -> bool {
	context.allocator = G_RENDERER_ALLOCATORS.temp_allocator
	defer free_all(G_RENDERER_ALLOCATORS.temp_allocator)

	materials_config := "app_data/renderer/config/materials.json"
	materials_json_data, file_read_ok := os.read_entire_file(materials_config)

	if file_read_ok == false {
		return false
	}
	
	// Parse the materials config file
	material_json_entries: []MaterialJSONEntry

	if err := json.unmarshal(materials_json_data, &material_json_entries); err != nil {
		log.errorf("Failed to read materials json: %s\n", err)
		return false
	}

	for material_json_entry in material_json_entries {
		material_ref := allocate_material_ref(common.create_name(material_json_entry.name))
		material := get_material(material_ref)

		material.desc.material_pass_ref = find_material_pass_by_name(
			material_json_entry.material_pass_name,
		)
		assert(material.desc.material_pass_ref != InvalidMaterialPassRef)

		// Features
		if len(material.desc.additional_shader_features) > 0 {
			material.desc.additional_shader_features = common.clone_string_array(
				material.desc.additional_shader_features, 
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		// Int params
		if len(material_json_entry.int_params) > 0 {
			material.desc.int_params = make(
				[]MaterialParam, 
				len(material_json_entry.int_params), 
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			for int_param, i in material_json_entry.int_params {
				material.desc.int_params[i].name = common.create_name(int_param.name)
				material.desc.int_params[i].num_components = u8(int_param.num_components)
			}
		}

		// Float params
		if len(material_json_entry.float_params) > 0 {
			material.desc.float_params = make(
				[]MaterialParam, 
				len(material_json_entry.float_params), 
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		
			for float_param, i in material_json_entry.float_params {
				material.desc.float_params[i].name = common.create_name(float_param.name)
					material.desc.float_params[i].num_components = u8(float_param.num_components)
			}
		}
		
		// Texture params
		if len(material_json_entry.texture_params) > 0 {
			material.desc.texture_params = make(
				[]MaterialTextureParam, 
				len(material_json_entry.texture_params), 
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		
			for texture_param, i in material_json_entry.texture_params {
				assert(texture_param.type in G_IMAGE_TYPE_NAME_MAPPING)
				material.desc.texture_params[i].name = common.create_name(texture_param.name)
				material.desc.texture_params[i].image_type = G_IMAGE_TYPE_NAME_MAPPING[texture_param.type]
			}
		}

		assert(create_material(material_ref))
	}

	return  true
}

//--------------------------------------------------------------------------//

@(private = "file")
allocate_material_params_buffer :: proc(
	p_material: ^MaterialResource,
) -> (bool, BufferSuballocation) {

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

	p_material.material_buffer_entry_size_in_bytes = u32(
		num_float_records * size_of(f32) + 
		num_int_records * size_of(u32) + 
		num_texture_records * size_of(u32)) * 4

	initial_material_buffer_size := 
		p_material.material_buffer_entry_size_in_bytes * 
		INITIAL_MATERIAL_BUFFER_ENTRIES_COUNT

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
material_allocate_entry :: proc(p_material_ref: MaterialRef) -> (u32, ^byte) {

	material := get_material(p_material_ref)
	material_buffer := get_buffer(INTERNAL.material_params_buffer_ref)

	// Check if we have some free entries in the free array 
	if len(material.free_material_instance_indices) > 0 {
		entry_idx := pop(&material.free_material_instance_indices)
		entry_ptr := mem.ptr_offset(material_buffer.mapped_ptr, 
			material.params_buffer.offset + entry_idx * material.material_buffer_entry_size_in_bytes)

		return entry_idx, entry_ptr
	}

	if material.next_material_instance_idx >= material.max_material_instance_entries {
		// @TODO grow the buffer and copy all of the data currently in there 
		// to a new material, preserving the indexes for current material instances
		assert(false)
	}

	entry_idx := material.next_material_instance_idx
	material.next_material_instance_idx += 1
	
	entry_ptr := mem.ptr_offset(material_buffer.mapped_ptr, 
		material.params_buffer.offset + entry_idx * material.material_buffer_entry_size_in_bytes)
		
	return entry_idx, entry_ptr
} 

//--------------------------------------------------------------------------//

material_free_entry :: proc(p_material_ref: MaterialRef, p_entry_idx: u32) {

	// @TODO shrink the buffer if less than half of the entries are used

	material := get_material(p_material_ref)

	append(&material.free_material_instance_indices, p_entry_idx)

	return
}

//--------------------------------------------------------------------------//
