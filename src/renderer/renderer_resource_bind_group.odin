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

BindGroupImageBindingFlagBits :: enum u8 {
	AddressSubresource,
}

BindGroupImageBindingFlags :: distinct bit_set[BindGroupImageBindingFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupImageBinding :: struct {
	binding:     u32,
	image_ref:   ImageRef,
	base_mip:    u32,
	base_array:  u32,
	mip_count:   u32,
	layer_count: u32,
	array_element: u32,
	flags:       BindGroupImageBindingFlags,
}
//---------------------------------------------------------------------------//

BindGroupBufferBinding :: struct {
	binding:     u32,
	buffer_ref:  BufferRef,
	offset:      u32,
	size:        u32,
	array_index: u32,
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
bind_group_init :: proc() {
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

	backend_bind_group_init()
}

//---------------------------------------------------------------------------//

bind_group_allocate :: proc(p_name: common.Name) -> BindGroupRef {
	ref := BindGroupRef(common.ref_create(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_name))
	bind_group := &g_resources.bind_groups[bind_group_get_idx(ref)]
	bind_group.desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

bind_group_create :: proc(p_bind_group_ref: BindGroupRef) -> bool {
	backend_bind_group_create(p_bind_group_ref) or_return
	return true
}

//---------------------------------------------------------------------------//

bind_group_update :: proc(p_bind_group_ref: BindGroupRef, p_bind_group_update: BindGroupUpdate) {
	backend_bind_group_update(p_bind_group_ref, p_bind_group_update)
}

//---------------------------------------------------------------------------//

bind_group_get_idx :: #force_inline proc(p_ref: BindGroupRef) -> u32 {
	return common.ref_get_idx(&G_BIND_GROUP_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_group_destroy :: proc(p_ref: BindGroupRef) {
	backend_bind_group_destroy(p_ref)
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
