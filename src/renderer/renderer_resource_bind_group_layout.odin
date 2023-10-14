package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:hash"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_LAYOUT_REF_ARRAY: common.RefArray(BindGroupLayoutResource)
@(private = "file")
G_BIND_GROUP_LAYOUT_RESOURCE_ARRAY: []BindGroupLayoutResource

//---------------------------------------------------------------------------//

BindGroupLayoutRef :: common.Ref(BindGroupLayoutResource)

//---------------------------------------------------------------------------//

InvalidBindGroupLayout := BindGroupLayoutRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

BindGroupLayoutBindingType :: enum u8 {
	Image,
	StorageImage,
	UniformBuffer,
	StorageBuffer,
	UniformBufferDynamic,
	StorageBufferDynamic,
	Sampler,
}

//---------------------------------------------------------------------------//

BindGroupLayoutBindingFlagBits :: enum u8 {
	WriteAccess,
	Dynamic, // Only used for buffers
}

//---------------------------------------------------------------------------//

BindGroupLayoutBindingFlags :: distinct bit_set[BindGroupLayoutBindingFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupLayoutBinding :: struct {
	type:          BindGroupLayoutBindingType,
	shader_stages: ShaderStageFlags,
	flags:         BindGroupLayoutBindingFlags,
	count:         u32,
}

//---------------------------------------------------------------------------//

BindGroupLayoutDesc :: struct {
	name:     common.Name,
	bindings: []BindGroupLayoutBinding,
}

//---------------------------------------------------------------------------//

BindGroupLayoutResource :: struct {
	using backend_bind_group_layout: BackendBindGroupLayoutResource,
	desc:                            BindGroupLayoutDesc,
	hash:                            u32,
	num_dynamic_offsets:             u8,
}

//---------------------------------------------------------------------------//

@(private)
init_bind_group_layouts :: proc() {
	G_BIND_GROUP_LAYOUT_REF_ARRAY = common.ref_array_create(
		BindGroupLayoutResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_BIND_GROUP_LAYOUT_RESOURCE_ARRAY = make(
		[]BindGroupLayoutResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_init_bind_groups()
}

//---------------------------------------------------------------------------//

allocate_bind_group_layout_ref :: proc(p_name: common.Name) -> BindGroupLayoutRef {
	ref := BindGroupLayoutRef(
		common.ref_create(BindGroupLayoutResource, &G_BIND_GROUP_LAYOUT_REF_ARRAY, p_name),
	)
	get_bind_group_layout(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_bind_group_layout :: proc(p_bind_group_layout_ref: BindGroupLayoutRef) -> bool {
	bind_group_layout := get_bind_group_layout(p_bind_group_layout_ref)
	bind_group_layout.hash = hash.adler32(mem.slice_to_bytes(bind_group_layout.desc.bindings))

	backend_create_bind_group_layout(p_bind_group_layout_ref, bind_group_layout) or_return

	bind_group_layout.num_dynamic_offsets = 0
	for binding in bind_group_layout.desc.bindings {
		if binding.type == .UniformBufferDynamic || binding.type == .StorageBufferDynamic {
			bind_group_layout.num_dynamic_offsets += 1
		}
	}
	return true
}

//---------------------------------------------------------------------------//

get_bind_group_layout :: proc(p_ref: BindGroupLayoutRef) -> ^BindGroupLayoutResource {
	return(
		&G_BIND_GROUP_LAYOUT_RESOURCE_ARRAY[common.ref_get_idx(&G_BIND_GROUP_LAYOUT_REF_ARRAY, p_ref)] \
	)
}

//---------------------------------------------------------------------------//

destroy_bind_group_layout :: proc(p_ref: BindGroupLayoutRef) {
	bind_group_layout := get_bind_group_layout(p_ref)
	backend_destroy_bind_group_layout(p_ref)

	common.ref_free(&G_BIND_GROUP_LAYOUT_REF_ARRAY, p_ref)

}

//---------------------------------------------------------------------------//
