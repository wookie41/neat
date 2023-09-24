
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:mem"
import "core:log"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

MaterialDesc :: struct {
	name:         common.Name,
	material_type_ref: MaterialTypeRef,
}

//---------------------------------------------------------------------------//

MaterialResource :: struct {
	desc:                      MaterialDesc,
	material_bind_group_ref:   BindGroupRef,
	material_buffer_entry_idx: u32,
}

//---------------------------------------------------------------------------//

MaterialRef :: common.Ref(MaterialResource)

//---------------------------------------------------------------------------//

InvalidMaterialRef := MaterialRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_REF_ARRAY: common.RefArray(MaterialResource)
@(private = "file")
G_MATERIAL_RESOURCE_ARRAY: []MaterialResource

//---------------------------------------------------------------------------//

init_material :: proc() -> bool {
	G_MATERIAL_REF_ARRAY = common.ref_array_create(
		MaterialResource,
		MAX_MATERIALS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MATERIAL_RESOURCE_ARRAY = make(
		[]MaterialResource,
		MAX_MATERIALS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	return true
}

//---------------------------------------------------------------------------//

deinit_material :: proc() {
}

//---------------------------------------------------------------------------//

create_material :: proc(p_material_ref: MaterialRef) -> bool {
	material := get_material(p_material_ref)
	material_type := get_material_type(material.desc.material_type_ref)

	// Create a copy of the material bind group
	pipeline := get_pipeline(material.pipeline_ref)
	material.material_bind_group_ref = create_bind_group(pipeline.pipeline_layout_ref, 0)

	// @TODO bind group updates when updating texture bindings

	// Request an entry in the material buffer
	material.material_buffer_entry_idx, material.material_buffer_entry_ptr =
		material_allocate_entry(material.desc.material_ref)

	return true
}

//---------------------------------------------------------------------------//

allocate_material_ref :: proc(p_name: common.Name) -> MaterialRef {
	ref := MaterialRef(
		common.ref_create(MaterialResource, &G_MATERIAL_REF_ARRAY, p_name),
	)
	get_material(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material :: proc(p_ref: MaterialRef) -> ^MaterialResource {
	return &G_MATERIAL_RESOURCE_ARRAY[common.ref_get_idx(&G_MATERIAL_REF_ARRAY, p_ref)]
}

//--------------------------------------------------------------------------//

destroy_material :: proc(p_ref: MaterialRef) {
	material := get_material(p_ref)
	material_free_entry(
		material.desc.material_ref,
		material.material_buffer_entry_idx,
	)
	common.ref_free(&G_MATERIAL_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_set_int1_param :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: int,
) {
	__material_set_param(int, p_material_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_set_int2_param :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.ivec2,
) {
	__material_set_param(
		glsl.ivec2,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_set_int3_param :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.ivec3,
) {
	__material_set_param(
		glsl.ivec3,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//
material_set_int4_param :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.ivec4,
) {
	__material_set_param(
		glsl.ivec4,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_set_int_param :: proc {
	material_set_int_param_1,
	material_set_int_param_2,
	material_set_int_param_3,
	material_set_int_param_4,
}

//--------------------------------------------------------------------------//

material_set_texture_slot :: proc(
	p_material_ref: MaterialRef,
	p_slot_name: common.Name,
	p_image_ref: ImageRef,
) {
	material := get_material(p_material_ref)
	material := get_material(material.desc.material_ref)

	param_index := 0
	for texture_param in material.desc.texture_params {
		if texture_param.name == p_slot_name {
			break
		}
		param_index += 1
	}

	val := (^u32)(
		mem.ptr_offset(
			material.material_buffer_entry_ptr,
			param_index * size_of(u32),
		),
	)

	image := get_image(p_image_ref)

	val^ = image.bindless_idx
}

//--------------------------------------------------------------------------//

@(private = "file")
__material_set_param :: #force_inline proc(
	$T: typeid,
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: T,
) {
	material := get_material(p_material_ref)
	material_type := get_material_type(material.desc.material_type_ref)

	if (p_name in material_type.offset_per_param) == false {
		log.warnf(
			"Param '%s' not found for MaterialType '%s'\n", 
			common.get_string(p_name), 
			common.get_string(material_type.desc.name))
		return
	}

	val := (^T)(
		mem.ptr_offset(
			material.material_buffer_entry_ptr,
			material_type.offset_per_param[p_name],
		),
	)

	val^ = p_value
}

//--------------------------------------------------------------------------//

material_set_float_param_1 :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: f32,
) {
	__material_set_param(f32, p_material_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_set_float_param_2 :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.vec2,
) {
	__material_set_param(
		glsl.vec2,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_set_float_param_3 :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.vec3,
) {
	__material_set_param(
		glsl.vec3,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//
material_set_float_param_4 :: proc(
	p_material_ref: MaterialRef,
	p_name: common.Name,
	p_value: glsl.vec4,
) {
	__material_set_param(
		glsl.vec4,
		p_material_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_set_float_param :: proc {
	material_set_float_param_1,
	material_set_float_param_2,
	material_set_float_param_3,
	material_set_float_param_4,
}
//--------------------------------------------------------------------------//