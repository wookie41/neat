package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

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
	desc:  MaterialInstanceDesc,
	flags: MaterialInstanceFlags,
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

@(private = "file")
INTERNAL: struct {
	material_properties_array: []MaterialProperties,
}

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
	INTERNAL.material_properties_array = make([]MaterialProperties, MAX_MATERIAL_INSTANCES)

	return true
}

//---------------------------------------------------------------------------//

deinit_material_instance :: proc() {
}


//---------------------------------------------------------------------------//

material_instance_update_dirty_materials :: proc() {
	for i in 0 ..< G_MATERIAL_INSTANCE_REF_ARRAY.alive_count {
		material_instance_ref := G_MATERIAL_INSTANCE_REF_ARRAY.alive_refs[i]
		material_instance := &g_resources.material_instances[get_material_instance_idx(material_instance_ref)]
		if .Dirty in material_instance.flags {
			material_instance_update_dirty_data(material_instance_ref)
		}
	}
}

//---------------------------------------------------------------------------//

@(private="file")
material_instance_update_dirty_data :: proc(p_material_instance_ref: MaterialInstanceRef) {
	material_instance_idx := get_material_instance_idx(p_material_instance_ref)
	material_instance := &g_resources.material_instances[material_instance_idx]

	material_instance_data_offset := size_of(MaterialProperties) * material_instance_idx

	// If material instance data is dirty, we need to issue a copy to the GPU
	request_buffer_upload(
		BufferUploadRequest {
			dst_buff = g_renderer_buffers.material_instances_buffer_ref,
			dst_buff_offset = material_instance_data_offset,
			dst_queue_usage = .Graphics,
			first_usage_stage = .VertexShader,
			size = size_of(MaterialProperties),
			data_ptr = material_instance_get_properties_ptr(p_material_instance_ref),
			flags = {.RunOnNextFrame},
		},
	)

	material_instance.flags -= {.Dirty}
}

//---------------------------------------------------------------------------//

create_material_instance :: proc(p_material_instance_ref: MaterialInstanceRef) -> bool {
	material_instance := &g_resources.material_instances[get_material_instance_idx(p_material_instance_ref)]
	material_instance.flags += {.Dirty}
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
	common.ref_free(&G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

material_instance_get_properties_ptr :: proc(
	p_material_instance_ref: MaterialInstanceRef,
) -> ^MaterialProperties {
	return &INTERNAL.material_properties_array[get_material_instance_idx(p_material_instance_ref)]
}

//--------------------------------------------------------------------------//

material_instance_mark_dirty :: proc(p_material_instance_ref: MaterialInstanceRef) {
	material_instance_idx := get_material_instance_idx(p_material_instance_ref)
	material_instance := &g_resources.material_instances[material_instance_idx]
	material_instance.flags += {.Dirty}
}

//--------------------------------------------------------------------------//
