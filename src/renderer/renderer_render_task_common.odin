package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"

//---------------------------------------------------------------------------//

@(private)
RenderTaskCommon :: struct {
	render_pass_ref:      RenderPassRef,
	material_pass_refs:   []MaterialPassRef,
	render_pass_bindings: RenderPassBindings,
	material_pass_type:   MaterialPassType,
}

//---------------------------------------------------------------------------//

@(private)
render_task_common_init :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_bind_group_ref: BindGroupRef,
	p_render_task_common: ^RenderTaskCommon,
	p_uniform_buffer_sizes: []u32 = {},
	p_input_buffer_sizes: []u32 = {},
	p_output_buffer_sizes: []u32 = {},
) -> (
	res: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Find the material pass type name
	material_pass_type_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"materialPassType",
	) or_return

	material_pass_type := material_pass_parse_type(material_pass_type_name) or_return

	render_pass_bindings: RenderPassBindings
	render_task_setup_render_pass_bindings(
		p_render_task_config,
		&render_pass_bindings,
		p_uniform_buffer_sizes,
		p_input_buffer_sizes,
		p_output_buffer_sizes,
	)

	defer if res == false {
		delete(render_pass_bindings.image_inputs, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(render_pass_bindings.image_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	}

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
				"Error when loading MeshRenderTask '%s' - material pass %d has no name\n",
				current_material_pass_element,
			)
			continue
		}

		material_pass_ref := find_material_pass_by_name(material_pass_name)
		material_pass := &g_resources.material_passes[get_material_pass_idx(material_pass_ref)]

		if material_pass_ref == InvalidMaterialPassRef {
			log.errorf(
				"Error when parsing render task config - unknown material pass '%s'\n",
				common.get_string(material_pass.desc.name),
			)
			continue
		}

		render_mesh_bind_group := &g_resources.bind_groups[bind_group_get_idx(p_bind_group_ref)]
		if material_pass_compile_for_type(
			   material_pass_ref,
			   material_pass_type,
			   render_pass_ref,
			   render_mesh_bind_group.desc.layout_ref,
		   ) ==
		   false {

			log.errorf(
				"Error when loading - failed to compile pso for material pass type '%s'\n",
				common.get_string(material_pass.desc.name),
			)

			continue
		}

		append(&material_pass_refs, material_pass_ref)

		log.infof("Loaded material pass %s\n", material_pass_name)
	}

	if len(material_pass_refs) == 0 {
		log.errorf("Failed to load render task - it doesn't have any material passes \n")
		return false
	}

	p_render_task_common.render_pass_ref = render_pass_ref
	p_render_task_common.material_pass_refs = make(
		[]MaterialPassRef,
		len(material_pass_refs),
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	for material_pass_ref, i in material_pass_refs {
		p_render_task_common.material_pass_refs[i] = material_pass_ref
	}

	p_render_task_common.render_pass_bindings = render_pass_bindings
	p_render_task_common.material_pass_type = material_pass_type

	return true
}

//---------------------------------------------------------------------------//
