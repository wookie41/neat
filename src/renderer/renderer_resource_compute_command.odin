package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"

import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

ComputeCommandDesc :: struct {
	name:                   common.Name,
	compute_shader_ref:     ShaderRef,
	bind_group_layout_refs: []BindGroupLayoutRef,
	push_constants:         []PushConstantDesc,
}

//---------------------------------------------------------------------------//

ComputeCommandResource :: struct {
	desc:            ComputeCommandDesc,
	pipeline_ref:    ComputePipelineRef,
	bind_group_refs: []BindGroupRef,
}

//---------------------------------------------------------------------------//

ComputeCommandRef :: common.Ref(ComputeCommandResource)

//---------------------------------------------------------------------------//

InvalidComputeCommandRef := ComputeCommandRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_COMPUTE_COMMAND_REF_ARRAY: common.RefArray(ComputeCommandResource)

//---------------------------------------------------------------------------//

@(private)
compute_commands_init :: proc() -> bool {
	g_resources.compute_commands = make_soa(
		#soa[]ComputeCommandResource,
		MAX_COMPUTE_COMMANDS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	G_COMPUTE_COMMAND_REF_ARRAY = common.ref_array_create(
		ComputeCommandResource,
		MAX_COMPUTE_COMMANDS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	return true
}

//---------------------------------------------------------------------------//

@(private)
compute_commands_deinit :: proc() {
}

//---------------------------------------------------------------------------//

compute_command_allocate_ref :: proc(
	p_name: common.Name,
	p_bind_group_layouts_count: u32,
	p_push_constants_count: u32,
) -> ComputeCommandRef {
	ref := ComputeCommandRef(
		common.ref_create(ComputeCommandResource, &G_COMPUTE_COMMAND_REF_ARRAY, p_name),
	)
	compute_command := &g_resources.compute_commands[compute_command_get_idx(ref)]
	compute_command.desc.name = p_name
	compute_command.desc.bind_group_layout_refs = make(
		[]BindGroupLayoutRef,
		p_bind_group_layouts_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	compute_command.desc.push_constants = make(
		[]PushConstantDesc,
		p_push_constants_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	compute_command.bind_group_refs = make(
		[]BindGroupRef,
		p_bind_group_layouts_count,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	return ref
}

//---------------------------------------------------------------------------//

compute_command_get_idx :: #force_inline proc(p_ref: ComputeCommandRef) -> u32 {
	return common.ref_get_idx(&G_COMPUTE_COMMAND_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

compute_command_create :: proc(p_ref: ComputeCommandRef) -> bool {
	compute_command := &g_resources.compute_commands[compute_command_get_idx(p_ref)]

	compute_command.pipeline_ref = compute_pipeline_allocate_ref(
		compute_command.desc.name,
		u32(len(compute_command.desc.bind_group_layout_refs)),
		u32(len(compute_command.desc.push_constants)),
	)

	compute_pipeline := &g_resources.compute_pipelines[get_compute_pipeline_idx(compute_command.pipeline_ref)]
	compute_pipeline.desc.bind_group_layout_refs = compute_command.desc.bind_group_layout_refs
	compute_pipeline.desc.push_constants = compute_command.desc.push_constants
	compute_pipeline.desc.compute_shader_ref = compute_command.desc.compute_shader_ref

	if compute_pipeline_create(compute_command.pipeline_ref) == false {
		compute_command_destroy(p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

compute_command_destroy :: proc(p_ref: ComputeCommandRef) {
	compute_command := &g_resources.compute_commands[compute_command_get_idx(p_ref)]

	delete(compute_command.desc.bind_group_layout_refs, G_RENDERER_ALLOCATORS.resource_allocator)
	delete(compute_command.desc.push_constants, G_RENDERER_ALLOCATORS.resource_allocator)

	compute_pipeline_destroy(compute_command.pipeline_ref)
}

//---------------------------------------------------------------------------//

compute_command_reset :: proc(p_ref: ComputeCommandRef) {
	compute_command := &g_resources.compute_commands[compute_command_get_idx(p_ref)]
	compute_command.pipeline_ref = InvalidComputePipelineRef
}

//---------------------------------------------------------------------------//

compute_command_set_bind_group :: proc(
	p_ref: ComputeCommandRef,
	p_target: u32,
	p_bind_group_ref: BindGroupRef,
) {
	compute_command := &g_resources.compute_commands[compute_command_get_idx(p_ref)]
	compute_command.bind_group_refs[p_target] = p_bind_group_ref
}

//---------------------------------------------------------------------------//

compute_command_dispatch :: proc(
	p_ref: ComputeCommandRef,
	p_cmd_buff_ref: CommandBufferRef,
	p_push_constants: []rawptr,
	p_dynamic_offsets: [][]u32,
	p_work_group_count: glsl.uvec3,
) {
	assert(p_work_group_count.x > 0 && p_work_group_count.y > 0 && p_work_group_count.z > 0)

	compute_command := &g_resources.compute_commands[compute_command_get_idx(p_ref)]

	compute_pipeline_bind(compute_command.pipeline_ref, p_cmd_buff_ref)

	for bind_group_ref, i in compute_command.bind_group_refs {
		if bind_group_ref == InvalidBindGroupRef {
			continue
		}
		bind_group_bind(
			p_cmd_buff_ref,
			compute_command.pipeline_ref,
			bind_group_ref,
			u32(i),
			nil if p_dynamic_offsets == nil else p_dynamic_offsets[i],
		)
	}

	backend_compute_command_dispatch(
		p_ref,
		p_cmd_buff_ref,
		compute_command.pipeline_ref,
		p_work_group_count,
		p_push_constants,
	)
}

//---------------------------------------------------------------------------//
