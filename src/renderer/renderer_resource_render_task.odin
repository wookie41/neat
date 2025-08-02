
package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"
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
	CascadeShadows,
	BuildHiZ,
	PrepareShadowCascades,
	ComputeAvgLuminance,
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	render_task_functions: map[RenderTaskType]RenderTaskFunctions,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_TASK_TYPE_MAPPING := map[string]RenderTaskType {
	"Mesh"                  = .Mesh,
	"CascadeShadows"        = .CascadeShadows,
	"FullScreen"            = .FullScreen,
	"BuildHiZ"              = .BuildHiZ,
	"ComputeAvgLuminance"   = .ComputeAvgLuminance,
	"PrepareShadowCascades" = .PrepareShadowCascades,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_RENDER_PASS_BUFFER_USAGE_MAPPING := map[string]RenderPassBufferUsage {
	"Uniform" = .Uniform,
	"General" = .General,
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

	// Init cascade shadows render task
	{
		render_task_fn: RenderTaskFunctions
		cascade_shadows_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.CascadeShadows] = render_task_fn
	}

	// Init build Hi-Z render task
	{
		render_task_fn: RenderTaskFunctions
		build_hiz_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.BuildHiZ] = render_task_fn
	}

	// Init build Compute avg luminance render task
	{
		render_task_fn: RenderTaskFunctions
		compute_avg_luminance_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.ComputeAvgLuminance] = render_task_fn
	}

	// Init prepare shadow cascades render task
	{
		render_task_fn: RenderTaskFunctions
		build_prepare_shadow_cascades_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.PrepareShadowCascades] = render_task_fn
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

	// Fill per frame uniform data
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[get_render_task_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].begin_frame(render_task_ref)
	}

	// Upload uniform data
	uniform_buffers_update(p_dt)

	// Render
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[get_render_task_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].render(render_task_ref, p_dt)
	}

	// Cleanup
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
	p_uniform_buffer_sizes: []u32 = {},
	p_input_buffer_sizes: []u32 = {},
	p_output_buffer_sizes: []u32 = {},
) -> bool {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	input_images := make([dynamic]RenderPassImageInput, temp_arena.allocator)
	global_input_images := make([dynamic]RenderPassImageInput, temp_arena.allocator)
	output_images := make([dynamic]RenderPassImageOutput, temp_arena.allocator)

	input_buffers := make([dynamic]RenderPassBufferInput, temp_arena.allocator)
	output_buffers := make([dynamic]RenderPassBufferOutput, temp_arena.allocator)

	// Load image inputs 
	load_image_inputs(p_render_task_config, "InputImage", &input_images)
	load_image_inputs(p_render_task_config, "GlobalImage", &global_input_images)

	// Load buffer inputs
	load_buffer_inputs(
		p_render_task_config,
		p_uniform_buffer_sizes,
		p_input_buffer_sizes,
		"InputBuffer",
		&input_buffers,
	)
	load_buffer_inputs(
		p_render_task_config,
		p_uniform_buffer_sizes,
		p_input_buffer_sizes,
		"GlobalBuffers",
		&input_buffers,
	)

	// Load image outputs
	current_element_idx := 0
	output_buffer_idx := 0
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

		image_ref := find_image(image_name)
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

			render_pass_output_image := RenderPassImageOutput {
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
		image := &g_resources.images[get_image_idx(image_ref)]
		for i in 0 ..< image.desc.mip_count {

			render_pass_output_image := RenderPassImageOutput {
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

	// Load buffer outputs
	current_element_idx = 0
	for {
		output_buffer_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			"OutputBuffer",
			current_element_idx,
		)

		if found == false {
			break
		}
		buffer_name, name_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			output_buffer_element_id,
			"name",
		)
		if name_found == false {
			log.error("Can't setup render task - buffer name missing")
			current_element_idx += 1
			continue
		}
		offset, _ := common.xml_get_u32_attribute(
			p_render_task_config.doc,
			output_buffer_element_id,
			"offset",
		)
		size, size_found := common.xml_get_u32_attribute(
			p_render_task_config.doc,
			output_buffer_element_id,
			"size",
		)
		if size_found == false {
			size = p_output_buffer_sizes[output_buffer_idx]
			output_buffer_idx += 1
		}

		buffer_ref := find_buffer(buffer_name)
		if buffer_ref == InvalidBufferRef {
			log.errorf("Can't setup render task - unknown buffer '%s'\n", buffer_name)
			current_element_idx += 1
			continue
		}

		render_pass_output_buffer := RenderPassBufferOutput {
			buffer_ref         = buffer_ref,
			offset             = offset,
			size               = size,
		}

		append(&output_buffers, render_pass_output_buffer)

		current_element_idx += 1
	}

	p_out_bindings.image_inputs = common.to_static_slice(
		input_images,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_out_bindings.global_image_inputs = common.to_static_slice(
		global_input_images,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_out_bindings.image_outputs = common.to_static_slice(
		output_images,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_out_bindings.buffer_inputs = common.to_static_slice(
		input_buffers,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	p_out_bindings.buffer_outputs = common.to_static_slice(
		output_buffers,
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

@(private = "file")
load_image_inputs :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_image_element_name: string,
	p_input_images: ^[dynamic]RenderPassImageInput,
) {
	current_element_idx := 0
	for {
		input_image_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			p_image_element_name,
			current_element_idx,
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
			log.error("Can't setup render task - image name missing")
			current_element_idx += 1
			continue
		}

		image_ref := find_image(image_name)
		image := &g_resources.images[get_image_idx(image_ref)]
		if image_ref == InvalidImageRef {
			log.errorf("Can't setup render task - unknown image '%s'\n", image.desc.name)
			current_element_idx += 1
			continue
		}

		mip, mip_found := common.xml_get_u32_attribute(
			p_render_task_config.doc,
			input_image_element_id,
			"mip",
		)
		array_layer, array_layer_found := common.xml_get_u32_attribute(
			p_render_task_config.doc,
			input_image_element_id,
			"arrayLayer",
		)

		append(
			p_input_images,
			RenderPassImageInput {
				image_ref = image_ref,
				base_mip = mip,
				mip_count = 1 if mip_found else image.desc.mip_count,
				base_array_layer = array_layer,
				array_layer_count = 1 if array_layer_found else image.desc.array_size,
			},
		)

		current_element_idx += 1
	}
}

//---------------------------------------------------------------------------//

load_buffer_inputs :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_uniform_buffer_sizes: []u32,
	p_input_buffer_sizes: []u32,
	p_buffer_element_name: string,
	p_input_buffers: ^[dynamic]RenderPassBufferInput,
) {
	current_element_idx := 0
	uniform_buffer_idx := 0
	input_buffer_idx := 0

	for {
		input_buffer_element_id, found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			p_buffer_element_name,
			current_element_idx,
		)

		if found == false {
			break
		}
		usage, usage_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			input_buffer_element_id,
			"usage",
		)
		if usage_found == false {
			log.errorf("Can't create render task - no buffer usage '%s'\n")
			current_element_idx += 1
			continue
		}

		if (usage in G_RENDER_PASS_BUFFER_USAGE_MAPPING) == false {
			log.errorf("Can't create render task - unknown buffer usage '%s'\n", usage)
			current_element_idx += 1
			continue
		}

		offset: u32
		size: u32

		buffer_usage := G_RENDER_PASS_BUFFER_USAGE_MAPPING[usage]
		buffer_ref: BufferRef


		if buffer_usage == .Uniform {
			buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref
			offset = common.INVALID_OFFSET
			size = p_uniform_buffer_sizes[uniform_buffer_idx]
			uniform_buffer_idx += 1
		} else {

			buffer_name, name_found := xml.find_attribute_val_by_key(
				p_render_task_config.doc,
				input_buffer_element_id,
				"name",
			)
			if name_found == false {
				log.error("Can't create render task - buffer name missing")
				current_element_idx += 1
				continue
			}
			buffer_offset, _ := common.xml_get_u32_attribute(
				p_render_task_config.doc,
				input_buffer_element_id,
				"offset",
			)
			buffer_size, size_not_found := common.xml_get_u32_attribute(
				p_render_task_config.doc,
				input_buffer_element_id,
				"size",
			)
			if size_not_found == false {
				buffer_size = p_input_buffer_sizes[input_buffer_idx]
				input_buffer_idx += 1
			}

			buffer_ref = find_buffer(buffer_name)

			if buffer_ref == InvalidBufferRef {
				log.errorf("Can't create render task - unknown buffer '%s'\n", buffer_name)
				current_element_idx += 1
				continue
			}

			offset = buffer_offset
			size = buffer_size
		}

		render_pass_input_buffer := RenderPassBufferInput {
			buffer_ref = buffer_ref,
			offset     = offset,
			usage      = buffer_usage,
			size       = size,
		}

		append(p_input_buffers, render_pass_input_buffer)

		current_element_idx += 1
	}

	//---------------------------------------------------------------------------//

}
