
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

MeshInstanceDesc :: struct {
	name:                  common.Name,
	mesh_ref:              MeshRef,
}

//---------------------------------------------------------------------------//

MeshInstanceResource :: struct {
	desc:                 MeshInstanceDesc,
}

//---------------------------------------------------------------------------//

MeshInstanceRef :: common.Ref(MeshInstanceResource)

//---------------------------------------------------------------------------//

InvalidMeshInstanceRef := MeshInstanceRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

init_mesh_instances :: proc() -> bool {
	g_resources.mesh_instances = make_soa(
		#soa[]MeshInstanceResource,
		MAX_MESH_INSTANCES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resource_refs.mesh_instances = common.ref_array_create(
		MeshInstanceResource,
		MAX_MESH_INSTANCES,
		G_RENDERER_ALLOCATORS.main_allocator,
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
		common.ref_create(MeshInstanceResource, &g_resource_refs.mesh_instances, p_name),
	)
	g_resources.mesh_instances[get_mesh_instance_idx(ref)].desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_mesh_instance_idx :: proc(p_ref: MeshInstanceRef) -> u32 {
	return common.ref_get_idx(&g_resource_refs.mesh_instances, p_ref)
}

//--------------------------------------------------------------------------//

destroy_mesh_instance :: proc(p_ref: MeshInstanceRef) {
	// mesh_instance := get_mesh_instance(p_ref)
	common.ref_free(&g_resource_refs.mesh_instances, p_ref)
}
