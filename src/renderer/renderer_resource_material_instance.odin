
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:mem"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

MaterialInstanceDesc :: struct {
	name:         common.Name,
	material_ref: MaterialRef,
}

//---------------------------------------------------------------------------//

MaterialInstanceResource :: struct {
	desc:                      MaterialInstanceDesc,
	material_bind_group_ref:   BindGroupRef,
	material_buffer_entry_idx: u32,
	material_buffer_entry_ptr: ^byte,
}

//---------------------------------------------------------------------------//

MaterialInstanceRef :: Ref(MaterialInstanceResource)

//---------------------------------------------------------------------------//

InvalidMaterialInstanceRef := MaterialInstanceRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_INSTANCE_REF_ARRAY: RefArray(MaterialInstanceResource)

//---------------------------------------------------------------------------//

init_material_instances :: proc() -> bool {
	G_MATERIAL_INSTANCE_REF_ARRAY = create_ref_array(
		MaterialInstanceResource,
		MAX_MATERIAL_INSTANCES,
	)
	return true
}

//---------------------------------------------------------------------------//

deinit_material_instances :: proc() {
}

//---------------------------------------------------------------------------//

create_material_instance :: proc(p_material_instance_ref: MaterialInstanceRef) -> bool {
	material_instance := get_material_instance(p_material_instance_ref)
	material := get_material(material_instance.desc.material_ref)

	// Create a copy of the material bind group
	pipeline := get_pipeline(material.pipeline_ref)
	material_instance.material_bind_group_ref = create_bind_group(pipeline.pipeline_layout_ref, 0)

	// @TODO bind group updates when updating texture bindings

	// Request an entry in the material buffer
	material_instance.material_buffer_entry_idx, material_instance.material_buffer_entry_ptr =
		material_allocate_entry(material_instance.desc.material_ref)

	return true
}

//---------------------------------------------------------------------------//

allocate_material_instance_ref :: proc(p_name: common.Name) -> MaterialInstanceRef {
	ref := MaterialInstanceRef(
		create_ref(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_name),
	)
	get_material_instance(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_instance :: proc(p_ref: MaterialInstanceRef) -> ^MaterialInstanceResource {
	return get_resource(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material_instance :: proc(p_ref: MaterialInstanceRef) {
	material_instance := get_material_instance(p_ref)
	material_free_entry(
		material_instance.desc.material_ref,
		material_instance.material_buffer_entry_idx,
	)
	free_ref(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_instance_set_int_param_1 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: int,
) {
	__material_instance_set_int_param(int, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_int_param_2 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec2,
) {
	__material_instance_set_int_param(
		glsl.ivec2,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_instance_set_int_param_3 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec3,
) {
	__material_instance_set_int_param(
		glsl.ivec3,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//
material_instance_set_int_param_4 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec4,
) {
	__material_instance_set_int_param(
		glsl.ivec4,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_instance_set_int_param :: proc {
	material_instance_set_int_param_1,
	material_instance_set_int_param_2,
	material_instance_set_int_param_3,
	material_instance_set_int_param_4,
}

//--------------------------------------------------------------------------//

material_instance_set_texture_slot :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_slot_name: common.Name,
	p_image_ref: ImageRef,
) {
	material_instance := get_material_instance(p_material_instance_ref)
	material := get_material(material_instance.desc.material_ref)

	param_index := 0
	for texture_param in material.desc.texture_params {
		if texture_param.name == p_slot_name {
			break
		}
		param_index += 1
	}

	val := (^u32)(
		mem.ptr_offset(
			material_instance.material_buffer_entry_ptr,
			param_index * size_of(u32),
		),
	)

	image := get_image(p_image_ref)

	val^ = image.bindless_idx
}

//--------------------------------------------------------------------------//

@(private = "file")
__material_instance_set_int_param :: #force_inline proc(
	$T: typeid,
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: T,
) {
	material_instance := get_material_instance(p_material_instance_ref)
	material := get_material(material_instance.desc.material_ref)

	param_index := 0
	for int_param in material.desc.int_params {
		if int_param.name == p_name {
			break
		}
		param_index += int(int_param.num_components)
	}

	val := (^T)(
		mem.ptr_offset(
			material_instance.material_buffer_entry_ptr,
			param_index * size_of(u32),
		),
	)

	val^ = p_value
}

//--------------------------------------------------------------------------//

material_instance_set_float_param_1 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: f32,
) {
	__material_instance_set_int_param(f32, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param_2 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec2,
) {
	__material_instance_set_int_param(
		glsl.vec2,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param_3 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec3,
) {
	__material_instance_set_float_param(
		glsl.vec3,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//
material_instance_set_float_param_4 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec4,
) {
	__material_instance_set_float_param(
		glsl.vec4,
		p_material_instance_ref,
		p_name,
		p_value,
	)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param :: proc {
	material_instance_set_float_param_1,
	material_instance_set_float_param_2,
	material_instance_set_float_param_3,
	material_instance_set_float_param_4,
}
//--------------------------------------------------------------------------//


@(private = "file")
__material_instance_set_float_param :: #force_inline proc(
	$T: typeid,
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: T,
) {
	material_instance := get_material_instance(p_material_instance_ref)
	material := get_material(material_instance.desc.material_ref)

	param_index := 0
	for float_param in material.desc.int_params {
		if float_param.name == p_name {
			break
		}
		param_index += int(float_param.num_components)
	}

	val := (^T)(
		mem.ptr_offset(
			material_instance.material_buffer_entry_ptr,
			param_index * size_of(f32),
		),
	)

	val^ = p_value
}

//--------------------------------------------------------------------------//
