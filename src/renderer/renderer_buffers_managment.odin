package renderer

//---------------------------------------------------------------------------//

import "../common"

//---------------------------------------------------------------------------//

@(private)
g_renderer_buffers: struct {
	mesh_instance_info_buffer_ref: BufferRef,
	material_instances_buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
buffer_management_init :: proc() -> bool {

	using g_renderer_buffers


	// Determine storage buffer flags and usage based on GPU type
	storage_buffer_flags := BufferDescFlags{.Dedicated}
	storage_buffer_usage := BufferUsageFlags{.StorageBuffer}
	if .IntegratedGPU in G_RENDERER.gpu_device_flags {
		storage_buffer_flags += {.Mapped}
	} else {
		storage_buffer_usage += {.TransferDst}
	}
	// Create the mesh instances info buffer
	{
		mesh_instance_info_buffer_ref = allocate_buffer_ref(
			common.create_name("MeshInstanceInfoBuffer"),
		)

		mesh_instance_info_buffer := &g_resources.buffers[get_buffer_idx(mesh_instance_info_buffer_ref)]

		mesh_instance_info_buffer.desc.flags = storage_buffer_flags
		mesh_instance_info_buffer.desc.usage = storage_buffer_usage
		mesh_instance_info_buffer.desc.size = size_of(MeshInstanceInfoData) * MAX_MESH_INSTANCES

		create_buffer(mesh_instance_info_buffer_ref) or_return
	}

	// Create material instances buffer 
	{
		material_instances_buffer_ref = allocate_buffer_ref(
			common.create_name("MaterialInstancesBuffer"),
		)

		material_instances_buffer := &g_resources.buffers[get_buffer_idx(material_instances_buffer_ref)]

		material_instances_buffer.desc.flags = storage_buffer_flags
		material_instances_buffer.desc.usage = storage_buffer_usage
        material_instances_buffer.desc.size = MATERIAL_INSTANCES_BUFFER_SIZE

		create_buffer(material_instances_buffer_ref) or_return
	}
    
	return true
}

//---------------------------------------------------------------------------//
