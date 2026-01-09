#+feature dynamic-literals

package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:math/linalg/glsl"

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

BindGroupDescFlagBits :: enum u8 {
	GlobalBindGroup,
}

BindGroupDescFlags :: distinct bit_set[BindGroupDescFlagBits;u8]

//---------------------------------------------------------------------------//

BindGroupImageBinding :: struct {
	binding:     u32,
	image_ref:   ImageRef,
	base_mip:    u32,
	base_array:  u32,
	mip_count:   u32,
	layer_count: u32,
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
	flags:      BindGroupDescFlags,
}

//---------------------------------------------------------------------------//

BindGroupResource :: struct {
	desc: BindGroupDesc,
}

//---------------------------------------------------------------------------//

BindGroupUpdate :: struct {
	images:            []BindGroupImageBinding,
	buffers:           []BindGroupBufferBinding,
	is_initial_update: bool,
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

bind_group_update :: proc(
	p_bind_group_ref: BindGroupRef,
	p_bindings: []Binding,
	p_is_initial_update: bool = false,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	buffers := make([dynamic]BindGroupBufferBinding, temp_arena.allocator)
	images := make([dynamic]BindGroupImageBinding, temp_arena.allocator)

	for binding, binding_index in p_bindings {

		switch b in binding {
		case InputImageBinding:
			image_binding := BindGroupImageBinding {
				binding     = u32(binding_index),
				image_ref   = b.image_ref,
				base_mip    = b.base_mip,
				base_array  = b.base_array_layer,
				mip_count   = b.mip_count,
				layer_count = b.array_layer_count,
			}

			if b.base_mip > 0 || b.base_array_layer > 0 {
				image_binding.flags += {.AddressSubresource}
			}

			append(&images, image_binding)

		case OutputImageBinding:
			image_binding := BindGroupImageBinding {
				binding     = u32(binding_index),
				image_ref   = b.image_ref,
				base_mip    = b.base_mip,
				base_array  = b.array_layer,
				mip_count   = b.mip_count,
				layer_count = 1,
				flags       = {.AddressSubresource},
			}

			append(&images, image_binding)

		case InputBufferBinding:
			buffer_binding := BindGroupBufferBinding {
				binding    = u32(binding_index),
				buffer_ref = b.buffer_ref,
				// The offset is expected to be updated dynamically
				offset     = 0 if b.usage == .Uniform else b.offset,
				size       = b.size,
			}

			append(&buffers, buffer_binding)

		case OutputBufferBinding:
			buffer_binding := BindGroupBufferBinding {
				binding    = u32(binding_index),
				buffer_ref = b.buffer_ref,
				offset     = b.offset,
				size       = b.size,
			}

			append(&buffers, buffer_binding)
		}
	}

	bind_group_update_info := BindGroupUpdate {
		buffers           = common.to_static_slice(buffers, temp_arena.allocator),
		images            = common.to_static_slice(images, temp_arena.allocator),
		is_initial_update = p_is_initial_update,
	}

	backend_bind_group_update(p_bind_group_ref, bind_group_update_info)
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


InputImageBindingFlagBits :: enum u8 {
	Storage,
}

InputImageBindingFlags :: distinct bit_set[InputImageBindingFlagBits;u8]

//---------------------------------------------------------------------------//

InputImageBinding :: struct {
	image_ref:         ImageRef,
	flags:             InputImageBindingFlags,
	base_mip:          u32,
	mip_count:         u32,
	base_array_layer:  u32,
	array_layer_count: u32,
}

//---------------------------------------------------------------------------//

OutputImageBindingFlagBits :: enum u8 {
	Clear,
}

//---------------------------------------------------------------------------//

OutputImageBindingFlags :: distinct bit_set[OutputImageBindingFlagBits;u8]

//---------------------------------------------------------------------------//

OutputImageBinding :: struct {
	image_ref:      ImageRef,
	temporal_index: u32,
	flags:          OutputImageBindingFlags,
	base_mip:       u32,
	mip_count:      u32,
	array_layer:    u32,
	clear_color:    glsl.vec4,
}

//---------------------------------------------------------------------------//

BufferBindingUsage :: enum u8 {
	Uniform,
	Storage,
	StorageDynamic,
}

@(private)
G_BUFFER_USAGE_MAPPING := map[string]BufferBindingUsage {
	"Uniform"        = .Uniform,
	"Storage"        = .Storage,
	"StorageDynamic" = .StorageDynamic,
}

//---------------------------------------------------------------------------//

InputBufferBinding :: struct {
	buffer_ref: BufferRef,
	offset:     u32,
	size:       u32,
	usage:      BufferBindingUsage,
}

//---------------------------------------------------------------------------//

OutputBufferBinding :: struct {
	buffer_ref: BufferRef,
	offset:     u32,
	size:       u32,
}

//---------------------------------------------------------------------------//

Binding :: union {
	InputImageBinding,
	OutputImageBinding,
	InputBufferBinding,
	OutputBufferBinding,
}

//---------------------------------------------------------------------------//

bind_group_create_for_bindings :: proc(
	p_name: common.Name,
	p_bindings: []Binding,
	p_is_compute: bool,
) -> (
	BindGroupRef,
	BindGroupLayoutRef,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	shader_stage: ShaderStageFlags = {.Compute} if p_is_compute else {.Pixel, .Vertex}

	bindings_count := len(p_bindings)

	// Create the layout
	bind_group_layout_ref := bind_group_layout_allocate(p_name, u32(bindings_count))
	bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_get_idx(bind_group_layout_ref)]

	images_count := 0
	buffers_count := 0


	for binding, binding_index in p_bindings {

		bind_group_layout.desc.bindings[binding_index].count = 1
		bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stage

		switch b in binding {
		case InputImageBinding:

			bind_group_layout.desc.bindings[binding_index].type = .Image
			bind_group_layout.desc.bindings[binding_index].count = b.array_layer_count
			images_count += 1

		case OutputImageBinding:
			if !p_is_compute {
				continue
			}

			bind_group_layout.desc.bindings[binding_index].count = b.mip_count
			bind_group_layout.desc.bindings[binding_index].type = .StorageImage
			images_count += 1

		case InputBufferBinding:
			switch b.usage {
			case .Uniform:
				bind_group_layout.desc.bindings[binding_index].type = .UniformBufferDynamic
			case .Storage:
				bind_group_layout.desc.bindings[binding_index].type = .StorageBuffer
			case .StorageDynamic:
				bind_group_layout.desc.bindings[binding_index].type = .StorageBufferDynamic
			}

			buffers_count += 1

		case OutputBufferBinding:
			bind_group_layout.desc.bindings[binding_index].type = .StorageBuffer
			buffers_count += 1
		}
	}

	if bind_group_layout_create(bind_group_layout_ref) == false {
		bind_group_layout_destroy(bind_group_layout_ref)
		return InvalidBindGroupRef, InvalidBindGroupLayoutRef
	}

	// Suboptimal, because we iterate over the bindings twice, first to create the layout
	// and then for the bind group itself, but bindings count is never too big and thus
	// I don't feel like refactoring more code :p

	// Create bind group
	bind_group_ref := bind_group_allocate(p_name)
	bind_group := &g_resources.bind_groups[bind_group_get_idx(bind_group_ref)]

	bind_group.desc.layout_ref = bind_group_layout_ref

	if bind_group_create(bind_group_ref) == false {
		bind_group_layout_destroy(bind_group_layout_ref)
		return InvalidBindGroupRef, InvalidBindGroupLayoutRef
	}

	// Update bind group
	bind_group_update(bind_group_ref, p_bindings, true)

	return bind_group_ref, bind_group_layout_ref
}

//---------------------------------------------------------------------------//
