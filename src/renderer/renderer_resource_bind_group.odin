package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_REF_ARRAY: common.RefArray(BindGroupResource)
@(private = "file")
G_BIND_GROUP_RESOURCE_ARRAY: []BindGroupResource

//---------------------------------------------------------------------------//

BindGroupRef :: common.Ref(BindGroupResource)

//---------------------------------------------------------------------------//

InvalidBindGroup := BindGroupRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

BindGroupBindingType :: enum u8 {
	SampledImage,
	StorageImage,
	StructuredBuffer,
}

//---------------------------------------------------------------------------//

BindGroupBinding :: struct {
	type:        BindGroupBindingType,
	usage_flags: BindGroupBindingType,
	count:       u32,
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
	using backend_bind_group: BackendBindGroupResource,
	desc:                     BindGroupDesc,
}

//---------------------------------------------------------------------------//

BindGroupUpdate :: struct {
	images:  []BindGroupImageBinding,
	buffers: []BindGroupBufferBinding,
}

//---------------------------------------------------------------------------//

@(private)
init_bind_groups :: proc() {
	G_BIND_GROUP_REF_ARRAY = common.ref_array_create(
		BindGroupResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_BIND_GROUP_RESOURCE_ARRAY = make(
		[]BindGroupResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_bind_groups()
}

//---------------------------------------------------------------------------//

allocate_bind_group_ref :: proc(p_name: common.Name) -> BindGroupRef {
	ref := BindGroupRef(common.ref_create(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_name))
	get_bind_group(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_bind_group :: proc(p_bind_group_ref: BindGroupRef) -> bool {
	bind_group := get_bind_group(p_bind_group_ref)
	backend_create_bind_group(p_bind_group_ref, bind_group) or_return
	return true
}

//---------------------------------------------------------------------------//

bind_group_update :: proc(p_bind_group_ref: BindGroupRef, p_bind_group_update: BindGroupUpdate) {
	backend_bind_group_update(p_bind_group_ref, p_bind_group_update)
}

//---------------------------------------------------------------------------//

get_bind_group :: proc(p_ref: BindGroupRef) -> ^BindGroupResource {
	return &G_BIND_GROUP_RESOURCE_ARRAY[common.ref_get_idx(&G_BIND_GROUP_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

destroy_bind_group :: proc(p_ref: BindGroupRef) {
	backend_destroy_bind_group(p_ref)
	common.ref_free(&G_BIND_GROUP_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_bind_group :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_ref: PipelineRef,
	p_bind_group_ref: BindGroupRef,
	p_target: u32,
	p_dynamic_offsets: []u32,
) {
	cmd_buff := get_command_buffer(p_cmd_buff_ref)
	pipeline := get_pipeline(p_pipeline_ref)
	bind_group := get_bind_group(p_bind_group_ref)
	backend_bind_bind_group(cmd_buff, pipeline, bind_group, p_target, p_dynamic_offsets)
}

//---------------------------------------------------------------------------//
