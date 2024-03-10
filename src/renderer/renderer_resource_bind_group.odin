package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_REF_ARRAY: common.RefArray(BindGroupResource)

//---------------------------------------------------------------------------//

BindGroupRef :: common.Ref(BindGroupResource)

//---------------------------------------------------------------------------//

InvalidBindGroupRef := BindGroupRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

BindGroupImageBinding :: struct {
	image_ref: ImageRef,
	mip:       u16,
}
//---------------------------------------------------------------------------//

BindGroupBufferBinding :: struct {
	buffer_ref: BufferRef,
	offset:     u32,
	size:       u32,
}

//---------------------------------------------------------------------------//

BindGroupDesc :: struct {
	name:       common.Name,
	layout_ref: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

BindGroupResource :: struct {
	desc: BindGroupDesc,
}

//---------------------------------------------------------------------------//

BindGroupUpdate :: struct {
	images:  []BindGroupImageBinding,
	buffers: []BindGroupBufferBinding,
}

//---------------------------------------------------------------------------//

@(private)
BindGroupsWithOffsets :: struct {
	bind_group_ref:  BindGroupRef,
	dynamic_offsets: []u32,
}

//---------------------------------------------------------------------------//

@(private)
init_bind_groups :: proc() {
	G_BIND_GROUP_REF_ARRAY = common.ref_array_create(
		BindGroupResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.bind_groups = make_soa(
		#soa[]BindGroupResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_bind_groups = make_soa(
		#soa[]BackendBindGroupResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	backend_init_bind_groups()
}

//---------------------------------------------------------------------------//

allocate_bind_group_ref :: proc(p_name: common.Name) -> BindGroupRef {
	ref := BindGroupRef(common.ref_create(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_name))
	bind_group := &g_resources.bind_groups[get_bind_group_idx(ref)]
	bind_group.desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_bind_group :: proc(p_bind_group_ref: BindGroupRef) -> bool {
	backend_create_bind_group(p_bind_group_ref) or_return
	return true
}

//---------------------------------------------------------------------------//

bind_group_update :: proc(p_bind_group_ref: BindGroupRef, p_bind_group_update: BindGroupUpdate) {
	backend_bind_group_update(p_bind_group_ref, p_bind_group_update)
}

//---------------------------------------------------------------------------//

get_bind_group_idx :: #force_inline proc(p_ref: BindGroupRef) -> u32 {
	return common.ref_get_idx(&G_BIND_GROUP_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_bind_group :: proc(p_ref: BindGroupRef) {
	backend_destroy_bind_group(p_ref)
	common.ref_free(&G_BIND_GROUP_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_group_bind :: proc {
	bind_group_bind_graphics,
	bind_group_bind_compute,
}

//---------------------------------------------------------------------------//

bind_group_bind_graphics :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_ref: GraphicsPipelineRef,
	p_bind_group_ref: BindGroupRef,
	p_target: u32,
	p_dynamic_offsets: []u32,
) {
	backend_bind_group_bind_graphics(
		p_cmd_buff_ref,
		p_pipeline_ref,
		p_bind_group_ref,
		p_target,
		p_dynamic_offsets,
	)
}

//---------------------------------------------------------------------------//

bind_group_bind_compute :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_ref: ComputePipelineRef,
	p_bind_group_ref: BindGroupRef,
	p_target: u32,
	p_dynamic_offsets: []u32,
) {
	backend_bind_group_bind_compute(
		p_cmd_buff_ref,
		p_pipeline_ref,
		p_bind_group_ref,
		p_target,
		p_dynamic_offsets,
	)
}

//---------------------------------------------------------------------------//
