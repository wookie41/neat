
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MeshInstanceDesc :: struct {
	name:                  common.Name,
	mesh_ref:              MeshRef,
	material_instance_ref: MaterialInstanceRef,
}

//---------------------------------------------------------------------------//

MeshInstanceResource :: struct {
	desc: MeshInstanceDesc,
}

//---------------------------------------------------------------------------//

MeshInstanceRef :: common.Ref(MeshInstanceResource)

//---------------------------------------------------------------------------//

InvalidMeshInstanceRef := MeshInstanceRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_INSTANCE_REF_ARRAY: common.RefArray(MeshInstanceResource)

//---------------------------------------------------------------------------//

init_mesh_instances :: proc() -> bool {
	G_MESH_INSTANCE_REF_ARRAY = common.ref_array_create(
		MeshInstanceResource,
		MAX_MESH_INSTANCES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.mesh_instances = make_soa(
		#soa[]MeshInstanceResource,
		MAX_MESH_INSTANCES,
		G_RENDERER_ALLOCATORS.resource_allocator,
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
		common.ref_create(MeshInstanceResource, &G_MESH_INSTANCE_REF_ARRAY, p_name),
	)
	g_resources.mesh_instances[get_mesh_instance_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_mesh_instance_idx :: proc(p_ref: MeshInstanceRef) -> u32 {
	return common.ref_get_idx(&G_MESH_INSTANCE_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_mesh_instance :: proc(p_ref: MeshInstanceRef) {
	// mesh_instance := get_mesh_instance(p_ref)
	common.ref_free(&G_MESH_INSTANCE_REF_ARRAY, p_ref)
}
