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
	name:        common.Name,
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

/** 
* Returns a new bind group based on layout of the provided bind group. 
* The bind group will be uninitialized, so the user must call update_bind_groups() for it
*/
clone_bind_groups :: proc(
	p_bind_group_refs: []BindGroupRef,
	p_allocator: mem.Allocator,
) -> (
	[]BindGroupRef,
	bool,
) {
	cloned_bind_group_refs := make([]BindGroupRef, len(p_bind_group_refs), p_allocator)
	for i in 0 ..< len(p_bind_group_refs) {
		cloned_bind_group_refs[i] = allocate_bind_group_ref(p_bind_group_refs[i].name)
		get_bind_group(cloned_bind_group_refs[i]).desc =
			get_bind_group(p_bind_group_refs[i]).desc
	}
	res := backend_clone_bind_groups(p_bind_group_refs, cloned_bind_group_refs)
	if res == false {
		destroy_bind_groups(cloned_bind_group_refs)
	}
	return cloned_bind_group_refs, res
}

//---------------------------------------------------------------------------//

clone_bind_group :: proc(p_bind_group_ref: BindGroupRef) -> BindGroupRef {
	bind_group := get_bind_group(p_bind_group_ref)
	cloned_bind_group_ref := allocate_bind_group_ref(bind_group.desc.name)
	cloned_bind_group := get_bind_group(cloned_bind_group_ref)

	cloned_bind_group.desc = bind_group.desc
	res := backend_clone_bind_groups({p_bind_group_ref}, {cloned_bind_group_ref})
	if res == false {
		destroy_bind_groups({cloned_bind_group_ref})
		return InvalidBindGroupRef
	}

	return cloned_bind_group_ref
}

//---------------------------------------------------------------------------//
