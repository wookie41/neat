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
		mesh_instance_info_buffer_ref = buffer_allocate(
			common.create_name("MeshInstanceInfoBuffer"),
		)

		mesh_instance_info_buffer := &g_resources.buffers[buffer_get_idx(mesh_instance_info_buffer_ref)]

		mesh_instance_info_buffer.desc = {
			flags = storage_buffer_flags,
			usage = storage_buffer_usage,
			size  = size_of(MeshInstanceInfoData) * MAX_MESH_INSTANCES,
		}

		buffer_create(mesh_instance_info_buffer_ref) or_return
	}

	// Create material instances buffer
	{
		material_instances_buffer_ref = buffer_allocate(
			common.create_name("MaterialInstancesBuffer"),
		)

		material_instances_buffer := &g_resources.buffers[buffer_get_idx(material_instances_buffer_ref)]
		material_instances_buffer.desc = {
			flags = storage_buffer_flags,
			usage = storage_buffer_usage,
			size  = MATERIAL_PROPERTIES_BUFFER_SIZE,
		}

		buffer_create(material_instances_buffer_ref) or_return
	}

	return true
}

//---------------------------------------------------------------------------//
