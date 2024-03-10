package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"

//---------------------------------------------------------------------------//

DrawCommandDesc :: struct {
	name:                   common.Name,
	vert_shader_ref:        ShaderRef,
	frag_shader_ref:        ShaderRef,
	bind_group_layout_refs: []BindGroupLayoutRef,
	push_constants:         []PushConstantDesc,
	vertex_buffer_ref:      BufferRef,
	index_buffer_ref:       BufferRef,
	draw_count:             u32,
	vertex_buffer_offset:   u64,
	index_buffer_offset:    u32,
	vertex_layout:          VertexLayout,
}

//---------------------------------------------------------------------------//

DrawCommandResource :: struct {
	desc:            DrawCommandDesc,
	pipeline_ref:    GraphicsPipelineRef,
	bind_group_refs: []BindGroupRef,
}

//---------------------------------------------------------------------------//

DrawCommandRef :: common.Ref(DrawCommandResource)

//---------------------------------------------------------------------------//

InvalidDrawCommandRef := DrawCommandRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_COMPUTE_COMMAND_REF_ARRAY: common.RefArray(DrawCommandResource)

//---------------------------------------------------------------------------//

@(private)
draw_commands_init :: proc() -> bool {
	g_resources.draw_commands = make_soa(
		#soa[]DrawCommandResource,
		MAX_COMPUTE_COMMANDS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	G_COMPUTE_COMMAND_REF_ARRAY = common.ref_array_create(
		DrawCommandResource,
		MAX_COMPUTE_COMMANDS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	return true
}

//---------------------------------------------------------------------------//

@(private)
draw_commands_deinit :: proc() {
}

//---------------------------------------------------------------------------//

draw_command_allocate_ref :: proc(
	p_name: common.Name,
	p_bind_group_layouts_count: u32,
	p_push_constants_count: u32,
) -> DrawCommandRef {
	ref := DrawCommandRef(
		common.ref_create(DrawCommandResource, &G_COMPUTE_COMMAND_REF_ARRAY, p_name),
	)
	draw_command_reset(ref)
	draw_command := &g_resources.draw_commands[draw_command_get_idx(ref)]
	draw_command.desc.name = p_name
	draw_command.desc.bind_group_layout_refs = make(
		[]BindGroupLayoutRef,
		p_bind_group_layouts_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	draw_command.desc.push_constants = make(
		[]PushConstantDesc,
		p_push_constants_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	draw_command.bind_group_refs = make(
		[]BindGroupRef,
		p_bind_group_layouts_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	return ref
}

//---------------------------------------------------------------------------//

draw_command_reset :: proc(p_ref: DrawCommandRef) {
	draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]
	draw_command.desc.vertex_buffer_ref = InvalidBufferRef
	draw_command.pipeline_ref = InvalidGraphicsPipelineRef
	draw_command.desc.index_buffer_ref = InvalidBufferRef
}

//---------------------------------------------------------------------------//

draw_command_get_idx :: #force_inline proc(p_ref: DrawCommandRef) -> u32 {
	return common.ref_get_idx(&G_COMPUTE_COMMAND_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

draw_command_create :: proc(p_ref: DrawCommandRef, p_render_pass_ref: RenderPassRef) -> bool {
	draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]

	draw_command.pipeline_ref = graphics_pipeline_allocate_ref(
		draw_command.desc.name,
		u32(len(draw_command.desc.bind_group_layout_refs)),
		u32(len(draw_command.desc.push_constants)),
	)

	graphics_pipeline := &g_resources.graphics_pipelines[get_graphics_pipeline_idx(draw_command.pipeline_ref)]
	graphics_pipeline.desc.bind_group_layout_refs = draw_command.desc.bind_group_layout_refs
	graphics_pipeline.desc.push_constants = draw_command.desc.push_constants
	graphics_pipeline.desc.vert_shader_ref = draw_command.desc.vert_shader_ref
	graphics_pipeline.desc.frag_shader_ref = draw_command.desc.frag_shader_ref
	graphics_pipeline.desc.render_pass_ref = p_render_pass_ref
	graphics_pipeline.desc.vertex_layout = draw_command.desc.vertex_layout

	if graphics_pipeline_create(draw_command.pipeline_ref) == false {
		draw_command_destroy(p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

draw_command_destroy :: proc(p_ref: DrawCommandRef) {
	draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]

	delete(draw_command.desc.bind_group_layout_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(draw_command.desc.push_constants, G_RENDERER_ALLOCATORS.resource_allocator)

	graphics_pipeline_destroy(draw_command.pipeline_ref)
}

//---------------------------------------------------------------------------//

draw_command_set_bind_group :: proc(
	p_ref: DrawCommandRef,
	p_target: u32,
	p_bind_group_ref: BindGroupRef,
) {
	draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]
	draw_command.bind_group_refs[p_target] = p_bind_group_ref
}

//---------------------------------------------------------------------------//

draw_command_execute :: proc(
	p_ref: DrawCommandRef,
	p_cmd_buff_ref: CommandBufferRef,
	p_push_constants: []rawptr,
	p_dynamic_offsets: [][]u32,
) {
	draw_command := &g_resources.draw_commands[draw_command_get_idx(p_ref)]

	graphics_pipeline_bind(draw_command.pipeline_ref, p_cmd_buff_ref)

	for bind_group_ref, i in draw_command.bind_group_refs {
		if bind_group_ref == InvalidBindGroupRef {
			continue
		}
		bind_group_bind(
			p_cmd_buff_ref,
			draw_command.pipeline_ref,
			bind_group_ref,
			u32(i),
			nil if p_dynamic_offsets == nil else p_dynamic_offsets[i],
		)
	}

	backend_draw_command_execute(
		p_ref,
		p_cmd_buff_ref,
		draw_command.pipeline_ref,
		p_push_constants,
	)
}

//---------------------------------------------------------------------------//
