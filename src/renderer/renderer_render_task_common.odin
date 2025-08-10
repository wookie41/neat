package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:encoding/xml"
import "core:log"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

@(private)
MaterialPassRenderTask :: struct {
	render_pass_ref:    RenderPassRef,
	material_pass_type: MaterialPassType,
	material_pass_refs: []MaterialPassRef,
	render_outputs:     []RenderPassOutput,
}

//---------------------------------------------------------------------------//

@(private)
render_task_init_material_pass_task :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_bind_group_ref: BindGroupRef,
	p_material_pass_render_task: ^MaterialPassRenderTask,
) -> (
	res: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Parse the material pass type name
	material_pass_type_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"materialPassType",
	) or_return

	material_pass_type := material_pass_parse_type(material_pass_type_name) or_return

	// Parse the render pass
	render_pass_name := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_render_task_config.render_task_element_id,
		"renderPass",
	) or_return
	render_pass_ref := render_pass_find_by_name(render_pass_name)
	if p_material_pass_render_task.render_pass_ref == InvalidRenderPassRef {
		return false
	}

	// Parse material passes
	material_pass_refs := parse_material_passes(
		p_render_task_config,
		render_pass_ref,
		p_bind_group_ref,
		material_pass_type,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	defer if res == false {
		delete(material_pass_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	// Parse outputs
	render_outputs := parse_output_images(
		p_render_task_config,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Fill the task data
	p_material_pass_render_task^ = MaterialPassRenderTask {
		material_pass_refs = material_pass_refs,
		material_pass_type = material_pass_type,
		render_pass_ref    = render_pass_ref,
		render_outputs     = render_outputs,
	}

	return true
}

//---------------------------------------------------------------------------//

@(private)
parse_material_passes :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_render_pass_ref: RenderPassRef,
	p_bind_group_ref: BindGroupRef,
	p_material_pass_type: MaterialPassType,
	p_allocator: mem.Allocator,
) -> []MaterialPassRef {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

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
		material_pass := &g_resources.material_passes[material_pass_get_idx(material_pass_ref)]

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
			   p_material_pass_type,
			   p_render_pass_ref,
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

	assert(len(material_pass_refs) > 0, "Failed to load render task - it doesn't have any material passes \n")

	return common.to_static_slice(material_pass_refs, p_allocator)
}

//---------------------------------------------------------------------------//

parse_output_images :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_allocator: mem.Allocator,
) -> []RenderPassOutput {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	current_element_idx := 0
	output_images := make([dynamic]RenderPassOutput, temp_arena.allocator)

	for {
		output_image_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			"OutputImage",
			len(output_images),
		)

		if found == false {
			break
		}
		image_name, name_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			output_image_element_id,
			"name",
		)
		if name_found == false {
			log.error("Can't setup render task - image name missing")
			current_element_idx += 1
			continue
		}

		image_ref := image_find(image_name)
		if image_ref == InvalidImageRef {
			log.errorf("Can't setup render task - unknown image '%s'\n", image_name)
			current_element_idx += 1
			continue
		}

		clear_values_str, clear_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			output_image_element_id,
			"clear",
		)
		clear_values: [4]f32

		if clear_found {

			clear_arr := strings.split(clear_values_str, ",", temp_arena.allocator)

			for str, i in clear_arr {
				val, ok := strconv.parse_f32(strings.trim_space(str))
				if ok {
					clear_values[i] = val
				} else {
					clear_values[i] = 0
				}
			}
		}


		mip, mip_found := common.xml_get_u32_attribute(
			p_render_task_config.doc,
			output_image_element_id,
			"mip",
		)

		// Use specific mip
		if mip_found {

			render_pass_output_image := RenderPassOutput {
				image_ref = image_ref,
				mip       = mip,
			}

			if clear_found {
				render_pass_output_image.clear_color = glsl.vec4(clear_values)
				render_pass_output_image.flags += {.Clear}
			}

			append(&output_images, render_pass_output_image)

			current_element_idx += 1
			continue
		}

		// Bind all mips
		image := &g_resources.images[image_get_idx(image_ref)]
		for i in 0 ..< image.desc.mip_count {

			render_pass_output_image := RenderPassOutput {
				image_ref = image_ref,
				mip       = i,
			}

			if clear_found {
				render_pass_output_image.clear_color = glsl.vec4(clear_values)
				render_pass_output_image.flags += {.Clear}
			}

			append(&output_images, render_pass_output_image)
		}

		current_element_idx += 1
	}

	return common.to_static_slice(output_images, p_allocator)
}

//---------------------------------------------------------------------------//

@(private)
render_task_destroy_material_pass_task :: proc(p_task: MaterialPassRenderTask) {
	delete(p_task.render_outputs, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(p_task.material_pass_refs, G_RENDERER_ALLOCATORS.resource_allocator)
}

//---------------------------------------------------------------------------//
