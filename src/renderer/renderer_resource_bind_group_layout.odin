package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:hash"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
G_BIND_GROUP_LAYOUT_REF_ARRAY: common.RefArray(BindGroupLayoutResource)

//---------------------------------------------------------------------------//

BindGroupLayoutRef :: common.Ref(BindGroupLayoutResource)

//---------------------------------------------------------------------------//

InvalidBindGroupLayoutRef := BindGroupLayoutRef {
	ref = c.UINT32_MAX,
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
	BindlessImageArray,
}

//---------------------------------------------------------------------------//

BindGroupLayoutBindingFlags :: distinct bit_set[BindGroupLayoutBindingFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupLayoutBinding :: struct {
	type:                  BindGroupLayoutBindingType,
	shader_stages:         ShaderStageFlags,
	flags:                 BindGroupLayoutBindingFlags,
	count:                 u32,
	immutable_sampler_idx: u32,
}

//---------------------------------------------------------------------------//

BindGroupLayoutFlagBits :: enum u8 {
	BindlessResources,
}

//---------------------------------------------------------------------------//

BindGroupLayoutFlags :: distinct bit_set[BindGroupLayoutFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupLayoutDesc :: struct {
	bindings: []BindGroupLayoutBinding,
	flags:    BindGroupLayoutFlags,
}

//---------------------------------------------------------------------------//

BindGroupLayoutResource :: struct {
	name:                common.Name,
	desc:                BindGroupLayoutDesc,
	hash:                u32,
	num_dynamic_offsets: u32,
}

//---------------------------------------------------------------------------//

@(private)
bind_group_layout_init :: proc() {
	G_BIND_GROUP_LAYOUT_REF_ARRAY = common.ref_array_create(
		BindGroupLayoutResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.bind_group_layouts = make_soa(
		#soa[]BindGroupLayoutResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_bind_group_layouts = make_soa(
		#soa[]BackendBindGroupLayoutResource,
		MAX_BIND_GROUPS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_bind_group_layout_init()
}

//---------------------------------------------------------------------------//

bind_group_layout_allocate :: proc(
	p_name: common.Name,
	p_binding_count: u32,
) -> BindGroupLayoutRef {
	ref := BindGroupLayoutRef(
		common.ref_create(BindGroupLayoutResource, &G_BIND_GROUP_LAYOUT_REF_ARRAY, p_name),
	)

	bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_get_idx(ref)]
	bind_group_layout^ = {}
	bind_group_layout.name = p_name
	bind_group_layout.desc = {
		bindings = make(
			[]BindGroupLayoutBinding,
			p_binding_count,
			G_RENDERER_ALLOCATORS.resource_allocator,
		),
	}
	return ref
}

//---------------------------------------------------------------------------//

bind_group_layout_create :: proc(p_bind_group_layout_ref: BindGroupLayoutRef) -> bool {
	bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_get_idx(p_bind_group_layout_ref)]
	bind_group_layout.hash = hash.crc32(mem.slice_to_bytes(bind_group_layout.desc.bindings))

	backend_bind_group_layout_create(p_bind_group_layout_ref) or_return

	bind_group_layout.num_dynamic_offsets = 0
	for binding in bind_group_layout.desc.bindings {
		if binding.type == .UniformBufferDynamic || binding.type == .StorageBufferDynamic {
			bind_group_layout.num_dynamic_offsets += 1
		}
	}
	return true
}

//---------------------------------------------------------------------------//

bind_group_layout_get_idx :: #force_inline proc(p_ref: BindGroupLayoutRef) -> u32 {
	return common.ref_get_idx(&G_BIND_GROUP_LAYOUT_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

bind_group_layout_destroy :: proc(p_ref: BindGroupLayoutRef) {
	bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_get_idx(p_ref)]
	delete(bind_group_layout.desc.bindings, G_RENDERER_ALLOCATORS.resource_allocator)

	backend_bind_group_layout_destroy(p_ref)

	common.ref_free(&G_BIND_GROUP_LAYOUT_REF_ARRAY, p_ref)

}

//---------------------------------------------------------------------------//
