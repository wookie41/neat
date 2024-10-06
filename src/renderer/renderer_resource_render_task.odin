
package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:encoding/xml"
import "core:log"
import "core:strconv"
import "core:strings"

//---------------------------------------------------------------------------//

RenderTaskDesc :: struct {
	name: common.Name,
	type: RenderTaskType,
}

//---------------------------------------------------------------------------//

RenderTaskRef :: common.Ref(RenderTaskResource)

//---------------------------------------------------------------------------//

RenderTaskType :: enum {
	Mesh,
	FullScreen,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	render_task_functions: map[RenderTaskType]RenderTaskFunctions,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_TYPE_MAPPING := map[string]RenderTaskType {
	"Mesh" = .Mesh,
	"FullScreen" = .FullScreen,
}

//---------------------------------------------------------------------------//

RenderTaskResource :: struct {
	desc:     RenderTaskDesc,
	data_ptr: rawptr,
}

//---------------------------------------------------------------------------//

RenderTaskFunctions :: struct {
	// Creates an instance of this render task and all of it's internal resources
	create_instance:  proc(
		p_render_task_ref: RenderTaskRef,
		p_render_task_config: ^RenderTaskConfig,
	) -> bool,
	// Called once, just before destroying the render task
	// This is the place when the render task should destroy it's internal resources
	destroy_instance: proc(p_render_task_ref: RenderTaskRef),
	// Called before the frame begin, i.e. before any draw/compute commands are issued
	begin_frame:      proc(p_render_task_ref: RenderTaskRef),
	// Called after the frame ends, i.e. after all draw and compute commands were submited
	end_frame:        proc(p_render_task_ref: RenderTaskRef),
	// Called each frame to run the render task
	render:           proc(p_render_task_ref: RenderTaskRef, dt: f32),
	// Pointer to data that is internally used but the render task
}

//---------------------------------------------------------------------------//

InvalidRenderTaskRef := RenderTaskRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_REF_ARRAY: common.RefArray(RenderTaskResource)

//---------------------------------------------------------------------------//

RenderTaskConfig :: struct {
	doc:                    ^xml.Document,
	render_task_element_id: xml.Element_ID,
}

//---------------------------------------------------------------------------//

init_render_tasks :: proc() -> bool {
	INTERNAL.render_task_functions = make(
		map[RenderTaskType]RenderTaskFunctions,
		len(RenderTaskType),
	)

	G_RENDER_TASK_REF_ARRAY = common.ref_array_create(
		RenderTaskResource,
		MAX_RENDER_TASKS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.render_tasks = make(
		[]RenderTaskResource,
		MAX_RENDER_TASKS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Init mesh render task
	{
		render_task_fn: RenderTaskFunctions
		mesh_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.Mesh] = render_task_fn
	}

	// Init fullscreen render task
	{
		render_task_fn: RenderTaskFunctions
		fullscreen_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.FullScreen] = render_task_fn
	}

	return true
}

//---------------------------------------------------------------------------//

deinit_render_tasks :: proc() {
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		destroy_render_task(G_RENDER_TASK_REF_ARRAY.alive_refs[i])
	}
	common.ref_array_clear(&G_RENDER_TASK_REF_ARRAY)
}

//---------------------------------------------------------------------------//

allocate_render_task_ref :: proc(p_name: common.Name) -> RenderTaskRef {
	ref := RenderTaskRef(common.ref_create(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_name))
	g_resources.render_tasks[get_render_task_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_render_task :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> bool {
	render_task := &g_resources.render_tasks[get_render_task_idx(p_render_task_ref)]
	return INTERNAL.render_task_functions[render_task.desc.type].create_instance(
		p_render_task_ref,
		p_render_task_config,
	)
}

//---------------------------------------------------------------------------//

get_render_task_idx :: #force_inline proc(p_ref: RenderTaskRef) -> u32 {
	return common.ref_get_idx(&G_RENDER_TASK_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_render_task :: proc(p_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[get_render_task_idx(p_ref)]
	INTERNAL.render_task_functions[render_task.desc.type].destroy_instance(p_ref)
	common.ref_free(&G_RENDER_TASK_REF_ARRAY, p_ref)
}


//--------------------------------------------------------------------------//

@(private)
render_task_map_name_to_type :: proc(p_type_name: string) -> (RenderTaskType, bool) {
	if p_type_name in G_RENDER_TASK_TYPE_MAPPING {
		return G_RENDER_TASK_TYPE_MAPPING[p_type_name], true
	}
	return nil, false
}

//--------------------------------------------------------------------------//

@(private)
render_tasks_update :: proc(p_dt: f32) {
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[get_render_task_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].begin_frame(render_task_ref)
	}

	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[get_render_task_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].render(render_task_ref, p_dt)
	}

	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[get_render_task_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].end_frame(render_task_ref)
	}
}

//--------------------------------------------------------------------------//

@(private)
render_task_setup_render_pass_bindings :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_out_bindings: ^RenderPassBindings,
) -> bool {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	input_images := make([dynamic]RenderPassImageInput, temp_arena.allocator)
	output_images := make([dynamic]RenderPassImageOutput, temp_arena.allocator)

	defer delete(input_images)
	defer delete(output_images)

	// Load inputs 
	for {
		input_image_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			"InputImage",
			len(input_images),
		)

		if found == false {
			break
		}

		image_name, name_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			input_image_element_id,
			"name",
		)
		if name_found == false {
			continue
		}

		image_ref := find_image(image_name)
		image := &g_resources.images[get_image_idx(image_ref)]
		if image_ref == InvalidImageRef {
			log.errorf("Can't start render task - unknown image '%s'\n", image.desc.name)
			continue
		}

		mip, mip_found := common.xml_get_u16_attribute(
			p_render_task_config.doc,
			input_image_element_id,
			"mip",
		)
		input_flags := RenderPassImageInputFlags{}

		if mip_found {
			input_flags += {.AddressSubresource}
		}

		append(
			&input_images,
			RenderPassImageInput{
				flags = input_flags,
				image_ref = image_ref,
				mip = mip if mip_found else 0,
			},
		)
	}

	// Load outputs
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
			continue
		}
		

		image_ref := find_image(image_name)
		if image_ref == InvalidImageRef {
			log.errorf("Can't start render task - unknown image '%s'\n", image_name)
			continue
		}

		render_pass_output_image := RenderPassImageOutput {
			image_ref = image_ref,
		}

		mip, mip_found := common.xml_get_u16_attribute(
			p_render_task_config.doc,
			output_image_element_id,
			"mip",
		)
		render_pass_output_image.mip = mip if mip_found else 0

		clear_values_str, clear_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			output_image_element_id,
			"clear",
		)
		if clear_found {
			render_pass_output_image.flags += {.Clear}
			clear_arr := strings.split(clear_values_str, ",", temp_arena.allocator)

			for str, i in clear_arr {
				val, ok := strconv.parse_f32(strings.trim_space(str))
				if ok {
					render_pass_output_image.clear_color[i] = val
				} else {
					render_pass_output_image.clear_color[i] = 0
				}
			}
		}

		append(&output_images, render_pass_output_image)
	}

	p_out_bindings.image_inputs = common.to_static_slice(
		input_images,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_out_bindings.image_outputs = common.to_static_slice(
		output_images,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	return true
}

//--------------------------------------------------------------------------//

render_task_begin_render_pass :: proc(
	p_render_pass_ref: RenderPassRef,
	p_render_pass_bindings: RenderPassBindings,
) {

	render_pass_begin_info := RenderPassBeginInfo {
		bindings = p_render_pass_bindings,
	}

	begin_render_pass(p_render_pass_ref, get_frame_cmd_buffer_ref(), &render_pass_begin_info)
}

//---------------------------------------------------------------------------//
