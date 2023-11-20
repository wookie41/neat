package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:mem"
import "core:reflect"

//---------------------------------------------------------------------------//

MaterialInstanceDesc :: struct {
	name:              common.Name,
	material_type_ref: MaterialTypeRef,
}

//---------------------------------------------------------------------------//

MaterialInstanceFlagBits :: enum u8 {
	Dirty,
}


MaterialInstanceFlags :: distinct bit_set[MaterialInstanceFlagBits;u8]

//---------------------------------------------------------------------------//

MaterialInstanceResource :: struct {
	desc:                                 MaterialInstanceDesc,
	material_properties_data_ptr:         ^byte,
	material_properties_buffer_entry_idx: u32,
	flags:                                MaterialInstanceFlags,
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

//---------------------------------------------------------------------------//

init_material_instances :: proc() -> bool {
	G_MATERIAL_INSTANCE_REF_ARRAY = common.ref_array_create(
		MaterialInstanceResource,
		MAX_MATERIAL_INSTANCES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.material_instances = make_soa(
		#soa[]MaterialInstanceResource,
		MAX_MATERIAL_INSTANCES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	return true
}

//---------------------------------------------------------------------------//

deinit_material_instance :: proc() {
}


//---------------------------------------------------------------------------//

material_instance_update_dirty_materials :: proc() {
	for material_instance_ref in G_MATERIAL_INSTANCE_REF_ARRAY.alive_refs {
		material_instance := &g_resources.material_instances[get_material_instance_idx(material_instance_ref)]
		if .Dirty in material_instance.flags {
			continue
		}
		material_instance_update_dirty_data(material_instance_ref)
	}
}

//---------------------------------------------------------------------------//

material_instance_update_dirty_data :: proc(p_material_instance_ref: MaterialInstanceRef) {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	material_type := &g_resources.material_types[get_material_type_idx(material_instance.desc.material_type_ref)]

	// If material instance data is dirty, we need to issue a copy to the GPU
	upload_request := request_buffer_upload(
		BufferUploadRequest{
			dst_buff = material_type_get_properties_buffer(),
			dst_buff_offset = material_type.properties_size_in_bytes *
			material_instance.material_properties_buffer_entry_idx,
			dst_queue_usage = .Graphics,
			size = material_type.properties_size_in_bytes,
		},
	)

	if upload_request.ptr == nil {
		material_instance.flags += {.Dirty}
		return
	}

	material_instance.flags -= {.Dirty}

	mem.copy(
		upload_request.ptr,
		material_instance.material_properties_data_ptr,
		reflect.size_of_typeid(material_type.desc.properties_struct_type),
	)
}

//---------------------------------------------------------------------------//

create_material_instance :: proc(p_material_instance_ref: MaterialInstanceRef) -> (ret: bool) {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	defer if ret == false {
		common.ref_free(&G_MATERIAL_INSTANCE_REF_ARRAY, p_material_instance_ref)
	}

	// Request an entry in the material buffer
	material_instance.material_properties_buffer_entry_idx, material_instance.material_properties_data_ptr =
		material_type_allocate_properties_entry(material_instance.desc.material_type_ref)

	if material_instance.material_properties_data_ptr == nil {
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

allocate_material_instance_ref :: proc(p_name: common.Name) -> MaterialInstanceRef {
	ref := MaterialInstanceRef(
		common.ref_create(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_name),
	)
	g_resources.material_instances[get_material_instance_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_material_instance_idx :: proc(p_ref: MaterialInstanceRef) -> u32 {
	return common.ref_get_idx(&G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_material_instance :: proc(p_ref: MaterialInstanceRef) {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_ref)]
	material_type_free_properties_entry(
		material_instance.desc.material_type_ref,
		material_instance.material_properties_buffer_entry_idx,
	)
	common.ref_free(&G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_instance_set_flags :: proc(p_material_instance_ref: MaterialInstanceRef, p_flags: u32) {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	flags_bitfield := (^u32)(material_instance.material_properties_data_ptr)
	flags_bitfield^ = p_flags
}

//--------------------------------------------------------------------------//

material_instance_get_flags :: proc(p_material_instance_ref: MaterialInstanceRef) -> u32 {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	return (^u32)(material_instance.material_properties_data_ptr)^
}

//--------------------------------------------------------------------------//

material_instance_get_flag :: proc {
	material_instance_get_flag_str,
	material_instance_get_flag_name,
}

//--------------------------------------------------------------------------//

@(private = "file")
material_instance_get_flag_str :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_flag_name: string,
) -> bool {
	return material_instance_get_flag_name(
		p_material_instance_ref,
		common.create_name(p_flag_name),
	)
}

//--------------------------------------------------------------------------//

@(private = "file")
material_instance_get_flag_name :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_flag_name: common.Name,
) -> bool {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	material_type := &g_resources.material_types[get_material_type_idx(material_instance.desc.material_type_ref)]

	// Find flag index 
	for flag_name, flag_idx in material_type.desc.flag_names {
		if common.name_equal(p_flag_name, flag_name) {
			flags := material_instance_get_flags(p_material_instance_ref)
			return (flags & (1 << u32(flag_idx))) > 0
		}
	}

	return false
}
//--------------------------------------------------------------------------//

material_instance_set_flag :: proc {
	material_instance_set_flag_str,
	material_instance_set_flag_name,
}

@(private = "file")
material_instance_set_flag_str :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_flag_name: string,
	p_value: bool,
) {
	material_instance_set_flag_name(
		p_material_instance_ref,
		common.create_name(p_flag_name),
		p_value,
	)
}

//--------------------------------------------------------------------------//

@(private = "file")
material_instance_set_flag_name :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	p_flag_name: common.Name,
	p_value: bool,
) {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	material_type := &g_resources.material_types[get_material_type_idx(material_instance.desc.material_type_ref)]

	// Find flag index and set it
	for flag_name, flag_idx in material_type.desc.flag_names {
		if common.name_equal(p_flag_name, flag_name) {
			flags_bitfield := (^u32)(material_instance.material_properties_data_ptr)
			if (p_value) {
				flags_bitfield^ |= (1 << u32(flag_idx))
			} else {
				flags_bitfield^ &= ~(1 << u32(flag_idx))
			}
			return
		}
	}
}

//--------------------------------------------------------------------------//

material_instance_get_properties_struct :: proc(
	p_material_instance_ref: MaterialInstanceRef,
	$T: typeid,
) -> ^T {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	ptr := (^T)(mem.ptr_offset(material_instance.material_properties_data_ptr, size_of(u32)))
	return ptr
}

//--------------------------------------------------------------------------//
