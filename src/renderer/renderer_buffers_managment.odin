package renderer

//---------------------------------------------------------------------------//

import "../common"

//---------------------------------------------------------------------------//

@(private)
g_renderer_buffers: struct {
	mesh_instance_info_buffer_ref:       BufferRef,
	material_instances_buffer_ref:       BufferRef,
	mesh_instanced_draw_info_buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE :: 2 * common.MEGABYTE

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
		material_instances_buffer.desc.size = MATERIAL_PROPERTIES_BUFFER_SIZE

		create_buffer(material_instances_buffer_ref) or_return
	}

	// Create buffer for instanced mesh draws
	{
		mesh_instanced_draw_info_buffer_ref = allocate_buffer_ref(
			common.create_name("MeshInstancedDrawInfo"),
		)

		mesh_instanced_draw_info_buffer := &g_resources.buffers[get_buffer_idx(mesh_instanced_draw_info_buffer_ref)]

		mesh_instanced_draw_info_buffer.desc.flags = {.Dedicated}
		mesh_instanced_draw_info_buffer.desc.usage = {.DynamicStorageBuffer}
		mesh_instanced_draw_info_buffer.desc.size =
			MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE * G_RENDERER.num_frames_in_flight

		if .IntegratedGPU in G_RENDERER.gpu_device_flags {
			mesh_instanced_draw_info_buffer.desc.flags += {.Mapped}
		} else {
			mesh_instanced_draw_info_buffer.desc.usage += {.TransferDst}
		}

		create_buffer(mesh_instanced_draw_info_buffer_ref) or_return
	}

	return true
}

//---------------------------------------------------------------------------//

@(private)
buffer_management_get_mesh_instanced_info_buffer_offset :: #force_inline proc() -> u32 {
	return MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE * get_frame_idx()
}

//---------------------------------------------------------------------------//
