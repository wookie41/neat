#+feature dynamic-literals

package renderer

//---------------------------------------------------------------------------//

import "../common"

import "core:c"
import "core:encoding/xml"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"
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
	VolumetricFog,
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
	"VolumetricFog"         = .VolumetricFog,
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
	render:           proc(p_render_task_ref: RenderTaskRef, p_dt: f32),
	// Called each frame so that the render task can draw debug ui
	draw_debug_ui:    proc(p_render_task_ref: RenderTaskRef),
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

render_task_init :: proc() -> bool {
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

	// Init volumetric fog render task
	{
		render_task_fn: RenderTaskFunctions
		volumetric_fog_render_task_init(&render_task_fn)
		INTERNAL.render_task_functions[.VolumetricFog] = render_task_fn
	}

	return true
}

//---------------------------------------------------------------------------//

render_task_deinit :: proc() {
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_destroy(G_RENDER_TASK_REF_ARRAY.alive_refs[i])
	}
	common.ref_array_clear(&G_RENDER_TASK_REF_ARRAY)
}

//---------------------------------------------------------------------------//

render_task_allocate :: proc(p_name: common.Name) -> RenderTaskRef {
	ref := RenderTaskRef(common.ref_create(RenderTaskResource, &G_RENDER_TASK_REF_ARRAY, p_name))
	g_resources.render_tasks[render_task_get_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

render_task_create :: proc(
	p_render_task_ref: RenderTaskRef,
	p_render_task_config: ^RenderTaskConfig,
) -> bool {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_render_task_ref)]
	return INTERNAL.render_task_functions[render_task.desc.type].create_instance(
		p_render_task_ref,
		p_render_task_config,
	)
}

//---------------------------------------------------------------------------//

render_task_get_idx :: #force_inline proc(p_ref: RenderTaskRef) -> u32 {
	return common.ref_get_idx(&G_RENDER_TASK_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

render_task_destroy :: proc(p_ref: RenderTaskRef) {
	render_task := &g_resources.render_tasks[render_task_get_idx(p_ref)]
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
render_task_update :: proc(p_dt: f32) {

	// Fill per frame uniform data
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[render_task_get_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].begin_frame(render_task_ref)
	}

	// Upload uniform data
	uniform_buffer_update(p_dt)

	// Render
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[render_task_get_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].render(render_task_ref, p_dt)
	}

	// Cleanup
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[render_task_get_idx(render_task_ref)]
		INTERNAL.render_task_functions[render_task.desc.type].end_frame(render_task_ref)
	}
}

//--------------------------------------------------------------------------//

@(private)
render_task_config_parse_bindings :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_is_compute_task: bool,
	p_buffer_sizes: []u32 = nil,
	p_bindings_tag_name: string = "",
	p_allocator: mem.Allocator = G_RENDERER_ALLOCATORS.resource_allocator,
) -> (
	out_bindings: []Binding,
	out_res: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	bindings := make([dynamic]Binding, temp_arena.allocator)

	bindings_element_id := p_render_task_config.render_task_element_id
	if len(p_bindings_tag_name) > 0 {

		element_id, bindings_tag_found := xml.find_child_by_ident(
			p_render_task_config.doc,
			p_render_task_config.render_task_element_id,
			p_bindings_tag_name,
		)
		if bindings_tag_found == false {
			log.errorf("Custom bindings tag '%s' not found\n", p_bindings_tag_name)
			return nil, false
		}

		bindings_element_id = element_id
	}

	bindings_tag := p_render_task_config.doc.elements[bindings_element_id]

	num_parsed_buffers := 0
	for child_tag in bindings_tag.value {
		switch child_id in child_tag {
		case string:
			continue
		case xml.Element_ID:
			child := p_render_task_config.doc.elements[child_id]

			//Skip commments. They have no name.
			if child.kind != .Element {continue}

			switch child.ident {
			case "InputImage":
				parse_input_image(p_render_task_config, child_id, &bindings) or_return
			case "InputBuffer":
				buffer_size: u32 = 0
				if num_parsed_buffers < len(p_buffer_sizes) {
					buffer_size = p_buffer_sizes[num_parsed_buffers]
					num_parsed_buffers += 1
				}

				parse_input_buffer(
					p_render_task_config,
					child_id,
					buffer_size,
					&bindings,
				) or_return
			case "OutputImage":
				if p_is_compute_task {
					parse_output_image(p_render_task_config, child_id, &bindings) or_return
				}

			case "OutputBuffer":
				buffer_size: u32 = 0
				if num_parsed_buffers < len(p_buffer_sizes) {
					buffer_size = p_buffer_sizes[num_parsed_buffers]
					num_parsed_buffers += 1
				}

				parse_output_buffer(
					p_render_task_config,
					child_id,
					buffer_size,
					&bindings,
				) or_return
			}
		}
	}


	return common.to_static_slice(bindings, p_allocator), true
}

//--------------------------------------------------------------------------//

render_task_render_pass_begin :: proc(
	p_render_pass_ref: RenderPassRef,
	p_outputs: []RenderPassOutput,
) {

	transition_render_outputs(p_outputs)

	render_pass_begin_info := RenderPassBeginInfo {
		outputs = p_outputs,
	}

	render_pass_begin(p_render_pass_ref, get_frame_cmd_buffer_ref(), &render_pass_begin_info)
}

//---------------------------------------------------------------------------//

@(private = "file")
parse_input_image :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_input_image_element_id: xml.Element_ID,
	p_out_bindings: ^[dynamic]Binding,
) -> bool {

	image_name, name_found := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_input_image_element_id,
		"name",
	)
	if name_found == false {
		log.error("Can't setup render task - image name missing")
		return false
	}

	image_ref := image_find(image_name)
	if image_ref == InvalidImageRef {
		log.errorf("Can't setup render task - unknown image '%s'\n", image_name)
		return false
	}
	image := &g_resources.images[image_get_idx(image_ref)]

	mip, mip_found := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_input_image_element_id,
		"mip",
	)
	array_layer, array_layer_found := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_input_image_element_id,
		"arrayLayer",
	)

	input_image := InputImageBinding {
		image_ref         = image_ref,
		base_mip          = mip,
		mip_count         = 1 if mip_found else image.desc.mip_count,
		base_array_layer  = array_layer,
		array_layer_count = 1 if array_layer_found else image.desc.array_size,
	}

	append(p_out_bindings, input_image)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
parse_input_buffer :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_input_buffer_element_id: xml.Element_ID,
	p_buffer_size: u32,
	p_out_bindings: ^[dynamic]Binding,
) -> bool {
	usage, usage_found := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_input_buffer_element_id,
		"usage",
	)
	if usage_found == false {
		log.errorf("Can't create render task - no buffer usage '%s'\n")
		return false
	}

	if (usage in G_BUFFER_USAGE_MAPPING) == false {
		log.errorf("Can't create render task - unknown buffer usage '%s'\n", usage)
		return false
	}

	offset := u32(0)

	buffer_usage := G_BUFFER_USAGE_MAPPING[usage]
	buffer_ref: BufferRef

	if buffer_usage == .Uniform {
		buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref
		offset = common.DYNAMIC_OFFSET
	} else {

		buffer_name, name_found := xml.find_attribute_val_by_key(
			p_render_task_config.doc,
			p_input_buffer_element_id,
			"name",
		)
		if name_found == false {
			log.error("Can't create render task - buffer name missing")
			return false
		}

		buffer_ref = buffer_find(buffer_name)

		if buffer_ref == InvalidBufferRef {
			log.errorf("Can't create render task - unknown buffer '%s'\n", buffer_name)
			return false
		}
	}

	buffer := &g_resources.buffers[buffer_get_idx(buffer_ref)]

	input_buffer := InputBufferBinding {
		buffer_ref = buffer_ref,
		usage      = buffer_usage,
		size       = p_buffer_size if p_buffer_size > 0 else buffer.desc.size,
	}

	append(p_out_bindings, input_buffer)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
parse_output_image :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_output_image_element_id: xml.Element_ID,
	p_out_bindings: ^[dynamic]Binding,
) -> bool {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	image_name, name_found := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_output_image_element_id,
		"name",
	)
	if name_found == false {
		log.error("Can't setup render task - image name missing")
		return false
	}

	image_ref := image_find(image_name)
	if image_ref == InvalidImageRef {
		log.errorf("Can't setup render task - unknown image '%s'\n", image_name)
		return false
	}

	clear_values_str, clear_found := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_output_image_element_id,
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


	image := &g_resources.images[image_get_idx(image_ref)]

	base_mip, _ := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_output_image_element_id,
		"baseMip",
	)

	mip_count, mip_found := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_output_image_element_id,
		"mipCount",
	)

	output_image_binding := OutputImageBinding {
		image_ref = image_ref,
		base_mip  = base_mip,
	}


	if clear_found {
		output_image_binding.clear_color = glsl.vec4(clear_values)
		output_image_binding.flags += {.Clear}
	}

	// use specific mip
	if !mip_found {
		mip_count = image.desc.mip_count
	}

	output_image_binding.mip_count = mip_count

	append(p_out_bindings, output_image_binding)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
parse_output_buffer :: proc(
	p_render_task_config: ^RenderTaskConfig,
	p_output_buffer_element_id: xml.Element_ID,
	p_buffer_size: u32,
	p_out_bindings: ^[dynamic]Binding,
) -> bool {

	buffer_name, name_found := xml.find_attribute_val_by_key(
		p_render_task_config.doc,
		p_output_buffer_element_id,
		"name",
	)
	if name_found == false {
		log.error("Can't setup render task - buffer name missing")
		return false
	}
	offset, _ := common.xml_get_u32_attribute(
		p_render_task_config.doc,
		p_output_buffer_element_id,
		"offset",
	)

	buffer_ref := buffer_find(buffer_name)
	if buffer_ref == InvalidBufferRef {
		log.errorf("Can't setup render task - unknown buffer '%s'\n", buffer_name)
		return false
	}

	buffer := &g_resources.buffers[buffer_get_idx(buffer_ref)]

	output_buffer := OutputBufferBinding {
		buffer_ref = buffer_ref,
		offset     = offset,
		size       = p_buffer_size if p_buffer_size > 0 else buffer.desc.size,
	}

	append(p_out_bindings, output_buffer)

	return true
}

//---------------------------------------------------------------------------//

@(private)
render_task_draw_debug_ui :: proc() {
	for i in 0 ..< G_RENDER_TASK_REF_ARRAY.alive_count {
		render_task_ref := G_RENDER_TASK_REF_ARRAY.alive_refs[i]
		render_task := &g_resources.render_tasks[render_task_get_idx(render_task_ref)]
		draw_debug_ui := INTERNAL.render_task_functions[render_task.desc.type].draw_debug_ui

		if (draw_debug_ui != nil) {
			draw_debug_ui(render_task_ref)
		}
	}
}
