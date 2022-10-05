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

//---------------------------------------------------------------------------//

TextureBindingFlagBits :: enum u32 {
	SampledImage,
	StorageImage,
}

TextureBindingFlags :: distinct bit_set[TextureBindingFlagBits;u32]

//---------------------------------------------------------------------------//

TextureBinding :: struct {
	slot:      u32,
	image_ref: ImageRef,
	flags:     TextureBindingFlags,
	count:     u32,
}

//---------------------------------------------------------------------------//

BufferBindingFlagBits :: enum u32 {
	UniformBuffer,
	DynamicUniformBuffer,
	StorageBuffer,
	DynamicStorageBuffer,
}

BufferBindingFlags :: distinct bit_set[BufferBindingFlagBits;u32]

//---------------------------------------------------------------------------//

BufferBinding :: struct {
	slot:       u32,
	buffer_ref: BufferRef,
	flags:      BufferBindingFlags,
}

//---------------------------------------------------------------------------//

BindGroupDesc :: struct {
	textures: []TextureBinding,
	buffers:  []BufferBinding,
}

//---------------------------------------------------------------------------//

BindGroupResource :: struct {
	using backend_bind_group: BackendBindGroupResource,
	desc:                     BindGroupDesc,
}

//---------------------------------------------------------------------------//

BindGroupBinding :: struct {
	bind_group_ref:      BindGroupRef,
	dynamic_offsets: []u32,
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

destroy_bind_group :: proc(p_ref: BindGroupRef) {
	free_ref(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_ref)
	backend_destroy_bind_group(p_ref)
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
	p_cmd_buff: CommandBufferRef,
	p_pipeline_type: PipelineType,
	p_pipeline_layout_ref: PipelineLayoutRef,
	p_bindings: []BindGroupBinding,
	p_samplers_bind_group_target: i32,
) {
	backend_bind_bind_groups(
		p_cmd_buff_ref,
		p_pipeline_type,
		p_pipeline_layout_ref,
		p_bindings,
		p_samplers_bind_group_target,
	)
}

//---------------------------------------------------------------------------//
