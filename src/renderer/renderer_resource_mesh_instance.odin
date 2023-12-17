
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

MeshInstanceDesc :: struct {
	name:     common.Name,
	mesh_ref: MeshRef,
}

//---------------------------------------------------------------------------//

MeshInstanceFlagBits :: enum u8 {
	MeshInstanceDataDirty,
}

//---------------------------------------------------------------------------//

MeshInstanceFlags :: distinct bit_set[MeshInstanceFlagBits;u8]

//---------------------------------------------------------------------------//

MeshInstanceResource :: struct {
	desc:         MeshInstanceDesc,
	model_matrix: glsl.mat4,
	flags:        MeshInstanceFlags,
}

//---------------------------------------------------------------------------//

MeshInstanceRef :: common.Ref(MeshInstanceResource)

//---------------------------------------------------------------------------//

InvalidMeshInstanceRef := MeshInstanceRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private)
MeshInstanceInfoData :: struct #packed {
	model_matrix: glsl.mat4,
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
	mesh_instance := &g_resources.mesh_instances[get_mesh_instance_idx(p_mesh_instance_ref)]
	mesh_instance.model_matrix = glsl.identity(glsl.mat4)
	mesh_instance.flags += {.MeshInstanceDataDirty}
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


//--------------------------------------------------------------------------//

@(private)
mesh_instance_send_transform_data :: proc() {

	for i in 0 ..< g_resource_refs.mesh_instances.alive_count {

		mesh_instance_ref := g_resource_refs.mesh_instances.alive_refs[i]
		mesh_instance_idx := get_mesh_instance_idx(mesh_instance_ref)
		mesh_instance := &g_resources.mesh_instances[mesh_instance_idx]

		if .MeshInstanceDataDirty in mesh_instance.flags {

			buffer_upload_request := BufferUploadRequest {
				dst_buff = g_renderer_buffers.mesh_instance_info_buffer_ref,
				dst_buff_offset = size_of(MeshInstanceInfoData) * mesh_instance_idx,
				dst_queue_usage = .Graphics,
				first_usage_stage = .VertexShader,
				size = size_of(MeshInstanceInfoData),
				flags = {.RunOnNextFrame},
				data_ptr = &mesh_instance.model_matrix,
			}

			buffer_upload_response := request_buffer_upload(buffer_upload_request)
			if buffer_upload_response.status == .Failed {
				continue
			}

			mesh_instance.flags -= {.MeshInstanceDataDirty}
		}
	}
}

//--------------------------------------------------------------------------//

mesh_instance_set_model_matrix :: proc(
	p_mesh_instance_ref: MeshInstanceRef,
	p_model_matrix: glsl.mat4x4,
) {
	mesh_instance := &g_resources.mesh_instances[get_mesh_instance_idx(p_mesh_instance_ref)]
	mesh_instance.model_matrix = p_model_matrix
	mesh_instance.flags += {.MeshInstanceDataDirty}
}

//--------------------------------------------------------------------------//
