package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "../common"

//---------------------------------------------------------------------------//

TextureBinding :: struct {
	name:      common.Name,
	image_ref: ImageRef,
}

//---------------------------------------------------------------------------//

BufferBinding :: struct {
	name:       common.Name,
	buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

BindGroupDesc :: struct {
	group:    u32,
	textures: []TextureBinding,
	buffers:  []BufferBinding,
}

//---------------------------------------------------------------------------//

BindGroupResource :: struct {
	using backend_bind_group: BackendBindGroupResource,
	desc:                     BindGroupDesc,
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

create_bind_group :: proc(p_ref: BindGroupRef) -> bool {
	bind_group := get_bind_group(p_ref)
	if backend_create_bind_group(p_ref, bind_group) == false {
		free_ref(BindGroupResource, &G_BIND_GROUP_REF_ARRAY, p_ref)
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
