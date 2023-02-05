
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MeshInstanceDesc :: struct {
	name:         common.Name,
	mesh_ref:     MeshRef,
	material_ref: MaterialRef,
}

//---------------------------------------------------------------------------//

MeshInstanceResource :: struct {
	desc: MeshInstanceDesc,
}

//---------------------------------------------------------------------------//

MeshInstanceRef :: Ref(MeshInstanceResource)

//---------------------------------------------------------------------------//

InvalidMeshInstanceRef := MeshInstanceRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_INSTANCE_REF_ARRAY: RefArray(MeshInstanceResource)

//---------------------------------------------------------------------------//

init_mesh_instances :: proc() -> bool {
	G_MESH_INSTANCE_REF_ARRAY = create_ref_array(
		MeshInstanceResource,
		MAX_MESH_INSTANCES,
	)
	return true
}

//---------------------------------------------------------------------------//

deinit_mesh_instances :: proc() {
}

//---------------------------------------------------------------------------//

create_mesh_instance :: proc(p_mesh_instance_ref: MeshInstanceRef) -> bool {
	return true
}

//---------------------------------------------------------------------------//

allocate_mesh_instance_ref :: proc(p_name: common.Name) -> MeshInstanceRef {
	ref := MeshInstanceRef(
		create_ref(MeshInstanceResource, &G_MESH_INSTANCE_REF_ARRAY, p_name),
	)
	get_mesh_instance(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_mesh_instance :: proc(p_ref: MeshInstanceRef) -> ^MeshInstanceResource {
	return get_resource(MeshInstanceResource, &G_MESH_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_mesh_instance :: proc(p_ref: MeshInstanceRef) {
	// mesh_instance := get_mesh_instance(p_ref)
	free_ref(MeshInstanceResource, &G_MESH_INSTANCE_REF_ARRAY, p_ref)
}
