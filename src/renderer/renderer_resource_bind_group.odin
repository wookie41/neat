package renderer

//---------------------------------------------------------------------------//

import "core:c"
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

BindingUsageStageFlagBits :: enum u8 {
	Vertex,
	Fragment,
	Compute,
}

BindingUsageStageFlags :: distinct bit_set[BindingUsageStageFlagBits;u8]

//---------------------------------------------------------------------------//

ImageBindingUsage :: enum u8 {
	SampledImage,
	StorageImage,
}

//---------------------------------------------------------------------------//

ImageBinding :: struct {
	slot:        u32,
	usage:       ImageBindingUsage,
	count:       u32,
	stage_flags: BindingUsageStageFlags,
}

//---------------------------------------------------------------------------//

BufferBinding :: struct {
	slot:         u32,
	buffer_usage: BufferUsageFlagBits,
	stage_flags:  BindingUsageStageFlags,
}

//---------------------------------------------------------------------------//

BindGroupDesc :: struct {
	name:    common.Name,
	target:  u32,
	images:  []ImageBinding,
	buffers: []BufferBinding,
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

BindGroupImageUpdate :: struct {
	slot:      u32,
	image_ref: ImageRef,
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

BindGroupRef :: Ref(BindGroupResource)

//---------------------------------------------------------------------------//

InvalidBindGroupRef := BindGroupRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_REF_ARRAY: RefArray(BindGroupResource)

//---------------------------------------------------------------------------//

@(private)
init_bind_groups :: proc() {
	G_BIND_GROUP_REF_ARRAY = create_ref_array(BindGroupResource, MAX_BIND_GROUPS)
	backend_init_bind_groups()
}

//---------------------------------------------------------------------------//

allocate_bind_group_ref :: proc(p_name: common.Name) -> BindGroupRef {
	ref := BindGroupRef(create_ref(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_name))
	get_bind_group(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_bind_groups :: proc(p_ref_array: []BindGroupRef) -> bool {
	if backend_create_bind_groups(p_ref_array) == false {
		for ref in p_ref_array {
			free_ref(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, ref)
		}
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_bind_group :: proc(p_ref: BindGroupRef) -> ^BindGroupResource {
	return get_resource(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_bind_groups :: proc(p_ref_array: []BindGroupRef) {
	backend_destroy_bind_groups(p_ref_array)
	for ref in p_ref_array {
		bind_group := get_bind_group(ref)
		if len(bind_group.desc.buffers) > 0 {
			delete(bind_group.desc.buffers, G_RENDERER_ALLOCATORS.resource_allocator)
		}
		if len(bind_group.desc.images) > 0 {
			delete(bind_group.desc.images, G_RENDERER_ALLOCATORS.resource_allocator)
		}
		free_ref(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, ref)
	}
}

//---------------------------------------------------------------------------//

update_bind_groups :: proc(p_updates: []BindGroupUpdate) {
	backend_update_bind_groups(p_updates)
}

//---------------------------------------------------------------------------//

/**
* Some backends like Vulkan require samplers to be bound separatly, other like DX12 allow to declare them in HLSL
* and that's when the p_samplers_bind_group_target is for.
* The backend interally creates all of the required samplers if required and create a group for them.
* The user can then choose which target it should be bound to, passing < 0 means that it's not needed
* If some backend doesn't need it it's simply a no-op/
*/
bind_bind_groups :: proc(
	p_cmd_buff_ref: CommandBufferRef,
	p_pipeline_ref: PipelineRef,
	p_bindings: []BindGroupBinding,
	p_samplers_bind_group_target: i32,
) {
	cmd_buff := get_command_buffer(p_cmd_buff_ref)
	pipeline := get_pipeline(p_pipeline_ref)

	backend_bind_bind_groups(cmd_buff, pipeline, p_bindings, p_samplers_bind_group_target)
}

//---------------------------------------------------------------------------//

/** 
* Returns a new bind group based on layout of the provided bind group. 
* The bind group will be uninitialized, so the user must call update_bind_groups() for it
*/
clone_bind_groups :: proc(p_bind_group_refs: []BindGroupRef, p_out_bind_groups: []BindGroupRef) -> bool {
	assert(len(p_bind_group_refs) == len(p_out_bind_groups))
	for i in 0..<len(p_bind_group_refs) {
		p_out_bind_groups[i] = allocate_bind_group_ref(p_bind_group_refs[i].name)
		get_bind_group(p_out_bind_groups[i]).desc = get_bind_group(p_out_bind_groups[i]).desc
	}
	return backend_clone_bind_groups(p_bind_group_refs, p_out_bind_groups)
}

//---------------------------------------------------------------------------//
