
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MaterialInstanceDesc :: struct {
	name:               common.Name,
}

//---------------------------------------------------------------------------//

MaterialInstanceResource :: struct {
	desc:                   MaterialInstanceDesc,
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
	G_MATERIAL_INSTANCE_REF_ARRAY = create_ref_array(MaterialInstanceResource, MAX_MATERIAL_INSTANCES)
	return true
}

//---------------------------------------------------------------------------//

deinit_material_instances :: proc() {
s}

//---------------------------------------------------------------------------//

create_material_instance :: proc(p_material_instance_ref: MaterialInstanceRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

allocate_material_instance_ref :: proc(p_name: common.Name) -> MaterialInstanceRef {
	ref := MaterialInstanceRef(create_ref(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_name))
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
	free_ref(MaterialInstanceResource, &G_MATERIAL_INSTANCE_REF_ARRAY, p_ref)
}

