package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:hash"
import "core:log"
import "core:math/linalg/glsl"
import "core:slice"

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	render_pass_ref:      RenderPassRef,
	material_pass_refs:   []MaterialPassRef,
	render_pass_bindings: RenderPassBindings,
	bind_group_ref:       BindGroupRef,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshBatch :: struct {
	vertex_buffer_offset: u32,
	index_buffer_offset:  u32,
	index_count:          u32,
	mesh_vertex_count:    u32,
	instance_count:       u32,
	material_type_ref:    MaterialTypeRef,
	instanced_draw_infos: [dynamic]MeshInstancedDrawInfo,
}

//---------------------------------------------------------------------------//

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
	task_bind_group_layout: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

mesh_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
	p_render_task_functions.create_instance = create_instance
	p_render_task_functions.destroy_instance = destroy_instance
	p_render_task_functions.begin_frame = begin_frame
	p_render_task_functions.end_frame = end_frame
	p_render_task_functions.render = render


	// Create a bind group layout for geometry pass
	{
		INTERNAL.task_bind_group_layout = allocate_bind_group_layout_ref(
			common.create_name("InstancedMesh"),
			1,
		)

		bind_group_layout := &g_resources.bind_group_layouts[get_bind_group_layout_idx(INTERNAL.task_bind_group_layout)]

		// Instance info data
		bind_group_layout.desc.bindings[0] = {
			count         = 1,
			shader_stages = {.Vertex, .Pixel, .Compute},
			type          = .StorageBufferDynamic,
		}

		create_bind_group_layout(INTERNAL.task_bind_group_layout)
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	geo_pass_desc := GeometryPassDescription {
		bind_group_layout_ref = INTERNAL.task_bind_group_layout,
		pass_type             = .InstancedMesh,
		vertex_shader_path    = common.create_name("geometry_pass_instanced_mesh.hlsl"),
		pixel_shader_path     = common.create_name("geometry_pass_instanced_mesh.hlsl"),
	}

	render_pass_bindings: RenderPassBindings
	render_task_setup_render_pass_bindings(p_render_task_config, &render_pass_bindings)

	defer if res == false {
		delete(render_pass_bindings.image_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(render_pass_bindings.image_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]

	// Find the render pass
	render_pass_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"renderPass",
	) or_return

	render_pass_ref := find_render_pass_by_name(render_pass_name)
	if render_pass_ref == InvalidRenderPassRef {
		return false
	}

	// Create the bind group
	task_bind_group_ref := allocate_bind_group_ref(common.create_name("MeshRenderTask"))
	{
		bind_group := &g_resources.bind_groups[get_bind_group_idx(task_bind_group_ref)]
		bind_group.desc.layout_ref = INTERNAL.task_bind_group_layout

		if create_bind_group(task_bind_group_ref) == false {
			return false
		}
	}

	// Update the bind group
	bind_group_update(
		task_bind_group_ref,
		{
			buffers = {
				{
					buffer_ref = g_renderer_buffers.mesh_instanced_draw_info_buffer_ref,
					size = MESH_INSTANCED_DRAW_INFO_BUFFER_SIZE,
				},
			},
		},
	)

	defer if res == false {
		destroy_bind_group(task_bind_group_ref)
	}


	// Gather material passes
	material_pass_refs := make([dynamic]MaterialPassRef, temp_arena.allocator)

	current_material_pass_element := 0

	for {
		material_pass_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			"MaterialPass",
			current_material_pass_element,
		)

		current_material_pass_element += 1

		if found == false {
			break
		}

		material_pass_name, name_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			material_pass_element_id,
			"name",
		)
		if name_found == false {
			log.errorf(
				"Error when loading Mesh render task '%s' - material pass %d has no name\n",
				current_material_pass_element,
			)
			continue
		}

		material_pass_ref := find_material_pass_by_name(material_pass_name)
		material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]

		if material_pass_ref == InvalidMaterialPassRef {
			log.errorf(
				"Error when loading Mesh render task '%s' - unknown material pass '%s'\n",
				common.get_string(mesh_render_task.desc.name),
				common.get_string(material_pass.desc.name),
			)
			continue
		}

		if material_pass_compile_geometry_pso(material_pass_ref, geo_pass_desc) == false {
			log.errorf(
				"Error when loading Mesh render task '%s' - failed to compile geometry pso for material pass '%s'\n",
				common.get_string(mesh_render_task.desc.name),
				common.get_string(material_pass.desc.name),
			)
			continue
		}

		append(&material_pass_refs, material_pass_ref)

		log.infof("Loaded material pass %s\n", material_pass_name)
	}

	if len(material_pass_refs) == 0 {
		log.errorf(
			"Failed to load Mesh render task '%s' - it doesn't have any material passes \n",
			common.get_string(mesh_render_task.desc.name),
		)
		return false
	}

	mesh_render_task_data := new(MeshRenderTaskData, G_RENDERER_ALLOCATORS.resource_allocator)
	mesh_render_task_data.render_pass_ref = render_pass_ref
	mesh_render_task_data.material_pass_refs = make(
		[]MaterialPassRef,
		len(material_pass_refs),
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	for material_pass_ref, i in material_pass_refs {
		mesh_render_task_data.material_pass_refs[i] = material_pass_ref
	}

	mesh_render_task.data_ptr = rawptr(mesh_render_task_data)
	mesh_render_task_data.render_pass_bindings = render_pass_bindings
	mesh_render_task_data.bind_group_ref = task_bind_group_ref

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
destroy_instance :: proc(p_render_task_ref: RenderTaskRef) {
	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)
	if mesh_render_task_data != nil {
		delete(mesh_render_task_data.material_pass_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	}
	if mesh_render_task_data.render_pass_bindings.image_inputs != nil {
		delete(
			mesh_render_task_data.render_pass_bindings.image_inputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	if mesh_render_task_data.render_pass_bindings.image_outputs != nil {
		delete(
			mesh_render_task_data.render_pass_bindings.image_outputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	free(mesh_render_task_data, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
begin_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
end_frame :: proc(p_render_task_ref: RenderTaskRef) {
}

//---------------------------------------------------------------------------//

@(private = "file")
render :: proc(p_render_task_ref: RenderTaskRef, dt: f32) {

	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena, common.MEGABYTE * 16)
	defer common.arena_delete(temp_arena)

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)

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
				mesh_batch.instance_count += 1
				append(&mesh_batch.instanced_draw_infos, instanced_draw_info)
				continue
			}

			mesh_batch := MeshBatch {
				index_buffer_offset  = mesh.index_buffer_allocation.offset + size_of(u32) * submesh.index_offset,
				index_count          = submesh.index_count,
				mesh_vertex_count    = mesh.vertex_count,
				instance_count       = 1,
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
		len(mesh_render_task_data.material_pass_refs),
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

	mesh_task_buffer_offsets := []u32{buffer_management_get_mesh_instanced_info_buffer_offset()}

	uniform_offsets := []u32 {
		g_uniform_buffers.frame_data_offset,
		g_uniform_buffers.view_data_offset,
	}

	// Aggregate instanced draw infos so we can issue a single copy and create the draw stream
	mesh_instanced_draws_infos := make([dynamic]MeshInstancedDrawInfo, temp_arena.allocator)
	num_instances_dispatched: u32 = 0

	draw_stream := draw_stream_create(temp_arena.allocator, common.create_name("GBuffer"))

	for material_type_ref, material_mesh_batches in mesh_batches_per_material_type {
		material_type := &g_resources.material_types[get_material_type_idx(material_type_ref)]
		for material_pass_ref in material_type.desc.material_passes_refs {

			// Only render this material pass if it's a part of the mesh render task
			is_material_pass_part_of_render_task := slice.contains(
				mesh_render_task_data.material_pass_refs,
				material_pass_ref,
			)

			if is_material_pass_part_of_render_task == false {
				continue
			}

			material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]
			geometry_pipeline_ref :=
				material_pass.geometry_pipeline_refs[transmute(u8)GeometryPassType.InstancedMesh]

			draw_stream_set_pipeline(&draw_stream, geometry_pipeline_ref)
			draw_stream_set_bind_group(
				&draw_stream,
				mesh_render_task_data.bind_group_ref,
				0,
				mesh_task_buffer_offsets,
			)
			draw_stream_set_bind_group(
				&draw_stream,
				G_RENDERER.uniforms_bind_group_ref,
				1,
				uniform_offsets,
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

				draw_stream_set_draw_count(&draw_stream, mesh_batch.index_count)
				draw_stream_set_instance_count(&draw_stream, mesh_batch.instance_count)
				draw_stream_set_first_instance(&draw_stream, num_instances_dispatched)
				draw_stream_submit_draw(&draw_stream)

				num_instances_dispatched += u32(len(mesh_batch.instanced_draw_infos))
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
			dst_buff = g_renderer_buffers.mesh_instanced_draw_info_buffer_ref,
			dst_buff_offset = buffer_management_get_mesh_instanced_info_buffer_offset(),
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

	// Dispatch the draw stream
	render_task_begin_render_pass(
		mesh_render_task_data.render_pass_ref,
		&mesh_render_task_data.render_pass_bindings,
	)

	draw_stream_dispatch(cmd_buff_ref, &draw_stream)

	end_render_pass(mesh_render_task_data.render_pass_ref, cmd_buff_ref)
}

//---------------------------------------------------------------------------//
