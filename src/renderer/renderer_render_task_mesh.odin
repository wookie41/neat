package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"

//---------------------------------------------------------------------------//

@(private)
MeshPushConstants :: struct #packed {
	mesh_instance_idx:     u32,
	material_instance_idx: u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshRenderTaskData :: struct {
	render_pass_ref:       RenderPassRef,
	material_pass_refs:    []MaterialPassRef,
	render_pass_interface: RenderPassInterface,
}

//---------------------------------------------------------------------------//

mesh_render_task_init :: proc(p_render_task_functions: ^RenderTaskFunctions) {
	p_render_task_functions.create_instance = create_instance
	p_render_task_functions.destroy_instance = destroy_instance
	p_render_task_functions.begin_frame = begin_frame
	p_render_task_functions.end_frame = end_frame
	p_render_task_functions.render = render
}


//---------------------------------------------------------------------------//

@(private = "file")
create_instance :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> (
	res: bool,
) {
	render_pass_interface: RenderPassInterface
	render_task_setup_render_pass_interface(p_render_task_config, &render_pass_interface)

	defer if res == false {
		delete(render_pass_interface.image_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(render_pass_interface.image_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]

	// Find the material pass
	render_pass_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"renderPass",
	) or_return

	render_pass_ref := find_render_pass_by_name(render_pass_name)
	if render_pass_ref == InvalidRenderPassRef {
		return false
	}

	// Gather material passes
	material_pass_refs := make([dynamic]MaterialPassRef, G_RENDERER_ALLOCATORS.temp_allocator)
	defer delete(material_pass_refs)

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
		if material_pass_ref == InvalidMaterialPassRef {
			log.errorf(
				"Error when loading Mesh render task '%s' - unknown material pass '%s'\n",
				common.get_string(mesh_render_task.desc.name),
			)
			continue
		}

		append(&material_pass_refs, material_pass_ref)

		log.infof("Loaded material pass %s\n", material_pass_name)
	}

	if len(material_pass_refs) == 0 {
		log.errorf(
			"Failed ot load Mesh render task '%s' - it doesn't have any material passes \n",
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
	mesh_render_task_data.render_pass_interface = render_pass_interface

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
	if mesh_render_task_data.render_pass_interface.image_inputs != nil {
		delete(
			mesh_render_task_data.render_pass_interface.image_inputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
	if mesh_render_task_data.render_pass_interface.image_outputs != nil {
		delete(
			mesh_render_task_data.render_pass_interface.image_outputs,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
	}
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
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	uniform_offsets := []u32{
		uniform_buffer_management_get_per_frame_offset(),
		uniform_buffer_management_get_per_view_offset(),
	}

	mesh_render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	mesh_render_task_data := (^MeshRenderTaskData)(mesh_render_task.data_ptr)

	// Create draw streams for each material pass
	draw_stream_per_material_pass := make(
		map[MaterialPassRef]DrawStream,
		len(mesh_render_task_data.material_pass_refs),
		G_RENDERER_ALLOCATORS.temp_allocator,
	)
	defer {
		for _, draw_stream in draw_stream_per_material_pass {
			draw_stream_destroy(draw_stream)
		}
		defer delete(draw_stream_per_material_pass)
	}

	// Create the draw stream for each material pass
	for material_pass_ref in mesh_render_task_data.material_pass_refs {
		draw_stream_per_material_pass[material_pass_ref] = draw_stream_create(temp_arena.allocator)

		material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]
		draw_stream := &draw_stream_per_material_pass[material_pass_ref]

		draw_stream_set_pipeline(draw_stream, material_pass.pipeline_ref)
		draw_stream_set_bind_group(
			draw_stream,
			G_RENDERER.global_bind_group_ref,
			1,
			uniform_offsets,
		)
		draw_stream_set_bind_group(
			draw_stream,
			G_RENDERER.bindless_textures_array_bind_group_ref,
			2,
			{},
		)
	}

	// Add meshes to the draw stream...
	for i in 0 ..< g_resource_refs.mesh_instances.alive_count {

		mesh_instance_ref := g_resource_refs.mesh_instances.alive_refs[i]

		mesh_instance_idx := get_mesh_instance_idx(mesh_instance_ref)
		mesh_instance := &g_resources.mesh_instances[mesh_instance_idx]
		mesh := &g_resources.meshes[get_mesh_idx(mesh_instance.desc.mesh_ref)]

		// .. each submesh ..
		for submesh, submesh_idx in mesh.desc.sub_meshes {

			material_instance_idx := get_material_instance_idx(submesh.material_instance_ref)
			material_instance := &g_resources.material_instances[material_instance_idx]
			material_type := &g_resources.material_types[get_material_type_idx(material_instance.desc.material_type_ref)]

			//... once for each material pass this submesh should be drawn in
			for material_pass_ref in material_type.desc.material_passes_refs {

				material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]
				draw_stream := &draw_stream_per_material_pass[material_pass_ref]

				if submesh_idx == 0 {
					draw_stream_set_vertex_buffer(
						draw_stream,
						mesh_get_global_vertex_buffer_ref(),
						0,
						mesh.vertex_buffer_allocation.offset,
					)
				}

				index_buffer_offset :=
					mesh.index_buffer_allocation.offset + size_of(u32) * submesh.data_offset

				draw_stream_set_index_buffer(
					draw_stream,
					mesh_get_global_index_buffer_ref(),
					.UInt32,
					index_buffer_offset,
				)

				mesh_push_constants := MeshPushConstants {
					mesh_instance_idx     = mesh_instance_idx,
					material_instance_idx = material_instance_idx,
				}

				draw_stream_add_push_constants(draw_stream, &mesh_push_constants)

				draw_stream_set_draw_count(draw_stream, submesh.data_count)
				draw_stream_set_instance_count(draw_stream, 1)
				draw_stream_submit_draw(draw_stream)
			}

		}
	}

	// Begin render pass
	render_task_begin_render_pass(
		mesh_render_task_data.render_pass_ref,
		&mesh_render_task_data.render_pass_interface,
	)
	cmd_buff_ref := get_frame_cmd_buffer_ref()


	// Dispatch the draw streams
	for material_pass_ref in draw_stream_per_material_pass {
		draw_stream_dispatch(cmd_buff_ref, &draw_stream_per_material_pass[material_pass_ref])
	}

	end_render_pass(mesh_render_task_data.render_pass_ref, cmd_buff_ref)
}

//---------------------------------------------------------------------------//
