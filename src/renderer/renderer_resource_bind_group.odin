package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:mem"
import "../common"

//---------------------------------------------------------------------------//

SamplerType :: enum {
	NearestClampToEdge,
	NearestClampToBorder,
	NearestRepeat,
	LinearClampToEdge,
	LinearClampToBorder,
	LinearRepeat,
}

SamplerNames := []string{
	"NearestClampToEdge",
	"NearestClampToBorder",
	"NearestRepeat",
	"LinearClampToEdge",
	"LinearClampToBorder",
	"LinearRepeat",
}

//---------------------------------------------------------------------------//

BindGroupDesc :: struct {
	name:                common.Name,
	pipeline_layout_ref: PipelineLayoutRef,
}

//---------------------------------------------------------------------------//

BindGroupResource :: struct {
	using backend_bind_group: BackendBindGroupResource,
	desc:                     BindGroupDesc,
}

//---------------------------------------------------------------------------//

BindGroupBinding :: struct {
	bind_group_ref:  BindGroupRef,
	dynamic_offsets: []u32,
}

//---------------------------------------------------------------------------//

EMPTY_BIND_GROUP_BINDING := BindGroupBinding {
	bind_group_ref = InvalidBindGroupRef,
}

//---------------------------------------------------------------------------//

BindGroupImageUpdateFlagBits :: enum u8 {
	AddressSubresource,
}

BindGroupImageUpdateFlags :: distinct bit_set[BindGroupImageUpdateFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupImageUpdate :: struct {
	slot:      u32,
	image_ref: ImageRef,
	flags:     BindGroupImageUpdateFlags,
	mip:       u32,
}

//---------------------------------------------------------------------------//

BindGroupBufferUpdate :: struct {
	slot:   u32,
	offset: u32,
	size:   u32,
	buffer: BufferRef,
}

//---------------------------------------------------------------------------//

BindGroupUpdate :: struct {
	bind_group_ref: BindGroupRef,
	image_updates:  []BindGroupImageUpdate,
	buffer_updates: []BindGroupBufferUpdate,
}

//---------------------------------------------------------------------------//


BindGroupRef :: common.Ref(BindGroupResource)

//---------------------------------------------------------------------------//

InvalidBindGroupRef := BindGroupRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_REF_ARRAY: common.RefArray(BindGroupResource)
@(private = "file")
G_BIND_GROUP_RESOURCE_ARRAY: []BindGroupResource

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

create_bind_groups :: proc(
	p_pipeline_layout_ref: PipelineLayoutRef,
	p_allocator: mem.Allocator,
) -> []BindGroupRef {

	pipeline_layout := get_pipeline_layout(p_pipeline_layout_ref)

	bind_group_refs := make(
		[]BindGroupRef,
		len(pipeline_layout.descriptor_set_layout_hashes),
		p_allocator,
	)

	for i in 0 ..< len(bind_group_refs) {
		bind_group_refs[i] = allocate_bind_group_ref(p_pipeline_layout_ref.name)
	}

	if backend_create_bind_groups(p_pipeline_layout_ref, pipeline_layout, bind_group_refs) ==
	   false {
		delete(bind_group_refs, p_allocator)
		for ref in bind_group_refs {
			common.ref_free(&G_BIND_GROUP_REF_ARRAY, ref)
		}
		return nil
	}
	return bind_group_refs
}

//---------------------------------------------------------------------------//

create_bind_group :: proc(
	p_pipeline_layout_ref: PipelineLayoutRef,
	p_bind_group_idx: u32,
) -> BindGroupRef {
	bind_group_ref := allocate_bind_group_ref(p_pipeline_layout_ref.name)
	bind_group := get_bind_group(bind_group_ref)
	pipeline_layout := get_pipeline_layout(p_pipeline_layout_ref)
	if backend_create_bind_group(
		   p_pipeline_layout_ref,
		   pipeline_layout,
		   p_bind_group_idx,
		   bind_group,
	   ) ==
	   false {
		common.ref_free(&G_BIND_GROUP_REF_ARRAY, bind_group_ref)
		return InvalidBindGroupRef
	}
	return bind_group_ref
}
//---------------------------------------------------------------------------//

get_bind_group :: proc(p_ref: BindGroupRef) -> ^BindGroupResource {
	return &G_BIND_GROUP_RESOURCE_ARRAY[common.ref_get_idx(&G_BIND_GROUP_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

destroy_bind_groups :: proc(p_ref_array: []BindGroupRef) {
	backend_destroy_bind_groups(p_ref_array)
	for ref in p_ref_array {
		common.ref_free(&G_BIND_GROUP_REF_ARRAY, ref)
	}
}

//---------------------------------------------------------------------------//

update_bind_groups :: proc(p_updates: []BindGroupUpdate) {
	backend_update_bind_groups(p_updates)
}

//---------------------------------------------------------------------------//

bind_bind_groups :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_ref: PipelineRef,
	p_bindings: []BindGroupBinding,
) {
	cmd_buff := get_command_buffer(p_cmd_buff_ref)
	pipeline := get_pipeline(p_pipeline_ref)

	backend_bind_bind_groups(cmd_buff, pipeline, p_bindings)
}

//---------------------------------------------------------------------------//
