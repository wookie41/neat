package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

MaterialInstanceDesc :: struct {
	name:              common.Name,
	material_type_ref: MaterialTypeRef,
}

//---------------------------------------------------------------------------//

MaterialInstanceResource :: struct {
	desc:                             MaterialInstanceDesc,
	material_params_buffer_ptr:       ^byte,
	material_params_buffer_entry_idx: u32,
}

//---------------------------------------------------------------------------//

MaterialInstanceRef :: common.Ref(MaterialInstanceResource)

//---------------------------------------------------------------------------//

InvalidMaterialInstanceRef := MaterialInstanceRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MATERIAL_INSTANCE_REF_ARRAY: common.RefArray(MaterialInstanceResource)
@(private = "file")
G_MATERIAL_INSTANCE_RESOURCE_ARRAY: []MaterialInstanceResource

//---------------------------------------------------------------------------//

init_material_instances :: proc() -> bool {
	G_MATERIAL_INSTANCE_REF_ARRAY = common.ref_array_create(
		MaterialInstanceResource,
		MAX_MATERIAL_INSTANCES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MATERIAL_INSTANCE_RESOURCE_ARRAY = make(
		[]MaterialInstanceResource,
		MAX_MATERIAL_INSTANCES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	return true
}

//---------------------------------------------------------------------------//

deinit_material_instance :: proc() {
}

//---------------------------------------------------------------------------//

create_material_instance :: proc(p_material_instance_ref: MaterialInstanceRef) -> (ret: bool) {
	material_instance := get_material_instance(p_material_instance_ref)
	defer if ret == false {
		common.ref_free(&G_MATERIAL_INSTANCE_REF_ARRAY, p_material_instance_ref)
	}

	// Request an entry in the material buffer
	material_instance.material_params_buffer_entry_idx, material_instance.material_params_buffer_ptr =
		material_type_allocate_params_entry(material_instance.desc.material_type_ref)

	if material_instance.material_params_buffer_ptr == nil {
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

allocate_material_instance_ref :: proc(p_name: common.Name) -> MaterialInstanceRef {
	ref := MaterialInstanceRef(
		common.ref_create(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_name),
	)
	get_material_instance(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_instance :: proc(p_ref: MaterialInstanceRef) -> ^MaterialInstanceResource {
	return(
		&G_MATERIAL_INSTANCE_RESOURCE_ARRAY[common.ref_get_idx(&G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)] \
	)
}

//--------------------------------------------------------------------------//

destroy_material_instance :: proc(p_ref: MaterialInstanceRef) {
	material_instance := get_material_instance(p_ref)
	material_type_free_params_entry(
		material_instance.desc.material_type_ref,
		material_instance.material_params_buffer_entry_idx,
	)
	common.ref_free(&G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_instance_set_int1_param :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: int,
) {
	__material_instance_set_param(int, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_int2_param :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec2,
) {
	__material_instance_set_param(glsl.ivec2, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_int3_param :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec3,
) {
	__material_instance_set_param(glsl.ivec3, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//
material_instance_set_int4_param :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.ivec4,
) {
	__material_instance_set_param(glsl.ivec4, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_int_param :: proc {
	material_instance_set_int1_param,
	material_instance_set_int2_param,
	material_instance_set_int3_param,
	material_instance_set_int4_param,
}

//--------------------------------------------------------------------------//

material_instance_set_texture_slot :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_slot_name: common.Name,
	p_image_ref: ImageRef,
) {
	image := &g_resources.image_resources[get_image_idx(p_image_ref)]
	material_instance_set_int1_param(p_material_instance_ref, p_slot_name, int(image.bindless_idx))
}

//--------------------------------------------------------------------------//

@(private = "file")
__material_instance_set_param :: #force_inline proc(
	$T: typeid,
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: T,
) {
	material_instance := get_material_instance(p_material_instance_ref)
	material_type := get_material_type(material_instance.desc.material_type_ref)

	if (p_name in material_type.offset_per_param) == false {
		log.warnf(
			"Param '%s' not found for MaterialType '%s'\n",
			common.get_string(p_name),
			common.get_string(material_type.desc.name),
		)
		return
	}

	val := (^T)(
		mem.ptr_offset(
			material_instance.material_params_buffer_ptr,
			material_type.offset_per_param[p_name],
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
	__material_instance_set_param(f32, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param_2 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec2,
) {
	__material_instance_set_param(glsl.vec2, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param_3 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec3,
) {
	__material_instance_set_param(glsl.vec3, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//
material_instance_set_float_param_4 :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_name: common.Name,
	p_value: glsl.vec4,
) {
	__material_instance_set_param(glsl.vec4, p_material_instance_ref, p_name, p_value)
}

//--------------------------------------------------------------------------//

material_instance_set_float_param :: proc {
	material_instance_set_float_param_1,
	material_instance_set_float_param_2,
	material_instance_set_float_param_3,
	material_instance_set_float_param_4,
}
//--------------------------------------------------------------------------//
