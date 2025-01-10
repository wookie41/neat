package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:hash"
import "core:log"
import "core:math/linalg/glsl"
import "core:slice"

//---------------------------------------------------------------------------//

@(private = "file")
MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE :: 2 * common.MEGABYTE

//---------------------------------------------------------------------------//

@(private = "file")
MeshBatch :: struct {
	vertex_buffer_offset: u32,
	index_buffer_offset:  u32,
	index_count:          u32,
	mesh_vertex_count:    u32,
	material_type_ref:    MaterialTypeRef,
	instanced_draw_infos: [dynamic]MeshInstancedDrawInfo,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshBatchKey :: distinct u32

//---------------------------------------------------------------------------//

@(private = "file")
MeshInstancedDrawInfo :: struct #packed {
	mesh_instance_idx:     u32,
	material_instance_idx: u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
calculate_mesh_batch_key :: proc(
	p_material_type_idx: u32,
	p_mesh_idx: u32,
	p_submesh_index: u32,
) -> MeshBatchKey {
	hash_input := []u32{p_material_type_idx, p_mesh_idx, p_submesh_index}
	mesh_batch_key := hash.crc32(slice.to_bytes(hash_input))
	return MeshBatchKey(mesh_batch_key)
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	job_bind_group_layout: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

@(private)
render_instanced_mesh_job_init :: proc() -> bool {

	// Create a bind group layout for task
	{
		INTERNAL.job_bind_group_layout = allocate_bind_group_layout_ref(
			common.create_name("RenderInstancedMesh"),
			2,
		)

		bind_group_layout := &g_resources.bind_group_layouts[get_bind_group_layout_idx(INTERNAL.job_bind_group_layout)]

		// Custom uniform data
		bind_group_layout.desc.bindings[0] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel},
			type          = .UniformBufferDynamic,
		}

		// Instance info data
		bind_group_layout.desc.bindings[1] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel},
			type          = .StorageBufferDynamic,
		}

		create_bind_group_layout(INTERNAL.job_bind_group_layout) or_return
	}

	return true
}

//---------------------------------------------------------------------------//

@(private)
RenderInstancedMeshJob :: struct {
	bind_group_ref:           BindGroupRef,
	instance_info_buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

@(private)
render_instanced_mesh_job_create :: proc(
	p_custom_data_size: u32 = size_of(u32),
) -> (
	mesh_job: RenderInstancedMeshJob,
	res: bool,
) {

	{
		// @TODO Resize this buffer if instance data wouldn't be able to fit it in
		// Create buffer for instanced mesh draws
		mesh_job.instance_info_buffer_ref = allocate_buffer_ref(
			common.create_name("MeshInstancedDrawInfo"),
		)

		mesh_instanced_draw_info_buffer := &g_resources.buffers[get_buffer_idx(mesh_job.instance_info_buffer_ref)]

		mesh_instanced_draw_info_buffer.desc.flags = {.Dedicated}
		mesh_instanced_draw_info_buffer.desc.usage = {.DynamicStorageBuffer}
		mesh_instanced_draw_info_buffer.desc.size =
			MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE * G_RENDERER.num_frames_in_flight

		if .IntegratedGPU in G_RENDERER.gpu_device_flags {
			mesh_instanced_draw_info_buffer.desc.flags += {.Mapped}
		} else {
			mesh_instanced_draw_info_buffer.desc.usage += {.TransferDst}
		}

		if create_buffer(mesh_job.instance_info_buffer_ref) == false {
			return {}, false
		}
	}

	defer if res == false {
		destroy_buffer(mesh_job.instance_info_buffer_ref)
	}

	// Create the bind group
	mesh_job.bind_group_ref = allocate_bind_group_ref(common.create_name("RenderInstancedMesh"))
	{
		bind_group := &g_resources.bind_groups[get_bind_group_idx(mesh_job.bind_group_ref)]
		bind_group.desc.layout_ref = INTERNAL.job_bind_group_layout

		if create_bind_group(mesh_job.bind_group_ref) == false {
			return {}, false
		}
	}

	// Update the bind group
	bind_group_update(
		mesh_job.bind_group_ref,
		{
			buffers = {
				{
					buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref,
					size = p_custom_data_size,
					binding = 0,
				},
				{
					buffer_ref = mesh_job.instance_info_buffer_ref,
					size = MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE,
					binding = 1,
				},
			},
		},
	)

	return mesh_job, true
}

//---------------------------------------------------------------------------//

@(private)
render_instanced_mesh_job_run :: proc(
	p_debug_name: common.Name,
	p_job_data: RenderInstancedMeshJob,
	p_render_pass_ref: RenderPassRef,
	p_render_views: []RenderView,
	p_render_pass_bindings_per_view: []RenderPassBindings,
	p_material_pass_refs: []MaterialPassRef,
	p_material_pass_type: MaterialPassType,
	p_custom_uniform_data_offsets: []u32 = {},
) {

	assert(len(p_render_pass_bindings_per_view) == len(p_render_views))

	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena, common.MEGABYTE * 16)
	defer common.arena_delete(temp_arena)

	// Batch meshes that share the same material
	mesh_batches := make(map[MeshBatchKey]MeshBatch, 16, temp_arena.allocator)

	for i in 0 ..< g_resource_refs.mesh_instances.alive_count {

		mesh_instance_ref := g_resource_refs.mesh_instances.alive_refs[i]

		mesh_instance_idx := get_mesh_instance_idx(mesh_instance_ref)
		mesh_instance := &g_resources.mesh_instances[mesh_instance_idx]
		mesh_idx := get_mesh_idx(mesh_instance.desc.mesh_ref)
		mesh := &g_resources.meshes[mesh_idx]

		// Skip mesh if it's data is still being uploaded
		if (mesh.data_upload_context.finished_uploads_count !=
			   mesh.data_upload_context.needed_uploads_count) {
			continue
		}

		// Add an instanced draw call for each submesh
		for submesh, submesh_idx in mesh.desc.sub_meshes {

			material_instance_idx := get_material_instance_idx(submesh.material_instance_ref)
			material_instance := &g_resources.material_instances[material_instance_idx]
			material_type_idx := get_material_type_idx(material_instance.desc.material_type_ref)

			mesh_batch_key := calculate_mesh_batch_key(
				material_type_idx,
				mesh_idx,
				u32(submesh_idx),
			)

			instanced_draw_info := MeshInstancedDrawInfo {
				mesh_instance_idx     = mesh_instance_idx,
				material_instance_idx = material_instance_idx,
			}

			if mesh_batch_key in mesh_batches {
				mesh_batch := &mesh_batches[mesh_batch_key]
				append(&mesh_batch.instanced_draw_infos, instanced_draw_info)
				continue
			}

			mesh_batch := MeshBatch {
				index_buffer_offset  = mesh.index_buffer_allocation.offset + size_of(u32) * submesh.index_offset,
				index_count          = submesh.index_count,
				mesh_vertex_count    = mesh.vertex_count,
				vertex_buffer_offset = mesh.vertex_buffer_allocation.offset,
				material_type_ref    = material_instance.desc.material_type_ref,
				instanced_draw_infos = make([dynamic]MeshInstancedDrawInfo, temp_arena.allocator),
			}

			append(&mesh_batch.instanced_draw_infos, instanced_draw_info)

			mesh_batches[mesh_batch_key] = mesh_batch
		}
	}

	// Gather all of the batches for each material type
	mesh_batches_per_material_type := make(
		map[MaterialTypeRef][dynamic]MeshBatch,
		len(p_material_pass_refs),
		temp_arena.allocator,
	)

	for _, mesh_batch in &mesh_batches {
		if mesh_batch.material_type_ref in mesh_batches_per_material_type {
			batches := &mesh_batches_per_material_type[mesh_batch.material_type_ref]
			append(batches, mesh_batch)
			continue
		}

		batches := make([dynamic]MeshBatch, temp_arena.allocator)
		append(&batches, mesh_batch)

		mesh_batches_per_material_type[mesh_batch.material_type_ref] = batches
	}

	// Aggregate instanced draw infos so we can issue a single copy and create the draw stream
	mesh_instanced_draws_infos := make([dynamic]MeshInstancedDrawInfo, temp_arena.allocator)
	num_instances_dispatched: u32 = 0

	draw_stream := draw_stream_create(temp_arena.allocator, p_debug_name)
	material_pass_type_idx := transmute(u8)p_material_pass_type

	mesh_instance_data_offset := MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE * get_frame_idx()

	for material_type_ref, material_mesh_batches in mesh_batches_per_material_type {
		material_type := &g_resources.material_types[get_material_type_idx(material_type_ref)]
		for material_pass_ref in material_type.desc.material_passes_refs {

			// Only render this material pass if it's a part of the mesh render task
			is_material_pass_part_of_render_task := slice.contains(
				p_material_pass_refs,
				material_pass_ref,
			)

			if is_material_pass_part_of_render_task == false {
				continue
			}

			material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]
			pipeline_ref := material_pass.pass_type_pipeline_refs[material_pass_type_idx]

			draw_stream_set_pipeline(&draw_stream, pipeline_ref)
			draw_stream_set_bind_group(
				&draw_stream,
				p_job_data.bind_group_ref,
				0,
				{common.INVALID_OFFSET, common.INVALID_OFFSET},
			)

			// Technically, these bind groups can be bound only once, as all material passes of the same material pass type share the same layout
			draw_stream_set_bind_group(
				&draw_stream,
				G_RENDERER.uniforms_bind_group_ref,
				1,
				{common.INVALID_OFFSET, common.INVALID_OFFSET},
			)

			draw_stream_set_bind_group(&draw_stream, G_RENDERER.globals_bind_group_ref, 2, nil)
			draw_stream_set_bind_group(&draw_stream, G_RENDERER.bindless_bind_group_ref, 3, nil)

			for mesh_batch in material_mesh_batches {

				for _, i in mesh_batch.instanced_draw_infos {
					append(&mesh_instanced_draws_infos, mesh_batch.instanced_draw_infos[i])
				}

				uv_offset := mesh_batch.mesh_vertex_count * size_of(glsl.vec3)
				normal_offset := uv_offset + mesh_batch.mesh_vertex_count * size_of(glsl.vec2)
				tangent_offset := normal_offset + mesh_batch.mesh_vertex_count * size_of(glsl.vec3)

				draw_stream_set_vertex_buffer(
					&draw_stream,
					mesh_get_global_vertex_buffer_ref(),
					0,
					mesh_batch.vertex_buffer_offset,
				)

				draw_stream_set_vertex_buffer(
					&draw_stream,
					mesh_get_global_vertex_buffer_ref(),
					1,
					mesh_batch.vertex_buffer_offset + uv_offset,
				)

				draw_stream_set_vertex_buffer(
					&draw_stream,
					mesh_get_global_vertex_buffer_ref(),
					2,
					mesh_batch.vertex_buffer_offset + normal_offset,
				)

				draw_stream_set_vertex_buffer(
					&draw_stream,
					mesh_get_global_vertex_buffer_ref(),
					3,
					mesh_batch.vertex_buffer_offset + tangent_offset,
				)

				draw_stream_set_index_buffer(
					&draw_stream,
					mesh_get_global_index_buffer_ref(),
					.UInt32,
					mesh_batch.index_buffer_offset,
				)

				num_instances := u32(len(mesh_batch.instanced_draw_infos))

				draw_stream_set_draw_count(&draw_stream, mesh_batch.index_count)
				draw_stream_set_instance_count(&draw_stream, num_instances)
				draw_stream_set_first_instance(&draw_stream, num_instances_dispatched)
				draw_stream_submit_draw(&draw_stream)

				num_instances_dispatched += num_instances
			}
		}
	}

	if len(mesh_instanced_draws_infos) == 0 {
		return
	}

	cmd_buff_ref := get_frame_cmd_buffer_ref()

	// Copy the mesh instanced draw info to the GPU
	instanced_draw_infos_size_in_bytes := u32(
		size_of(MeshInstancedDrawInfo) * len(mesh_instanced_draws_infos),
	)

	upload_response := request_buffer_upload(
		BufferUploadRequest {
			dst_buff = p_job_data.instance_info_buffer_ref,
			dst_buff_offset = mesh_instance_data_offset,
			dst_queue_usage = .Graphics,
			first_usage_stage = .VertexShader,
			size = instanced_draw_infos_size_in_bytes,
			data_ptr = raw_data(mesh_instanced_draws_infos),
		},
	)

	if upload_response.status == .Failed {
		log.warn("Failed to copy mesh instanced draw info\n")
		return
	}

	// Dispatch the draw stream for each view
	for i in 0 ..< len(p_render_views) {

		render_view := p_render_views[i]
		bindings := p_render_pass_bindings_per_view[i]

		// If custom uniform data is not needed, then just set the offset to 0 for user convenience
		custom_uniform_data_offset :=
			p_custom_uniform_data_offsets[i] if i < len(p_custom_uniform_data_offsets) else 0

		dynamic_offsets := []u32 {
			custom_uniform_data_offset,
			mesh_instance_data_offset,
			g_uniform_buffers.frame_data_offset,
			uniform_buffer_create_view_data(render_view),
		}

		render_task_begin_render_pass(p_render_pass_ref, bindings)

		draw_stream_dispatch(cmd_buff_ref, &draw_stream, dynamic_offsets)
		draw_stream_reset(&draw_stream)

		end_render_pass(p_render_pass_ref, cmd_buff_ref)
	}
}
