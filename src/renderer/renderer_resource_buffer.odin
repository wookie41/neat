package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "../common"

//---------------------------------------------------------------------------//

BufferDescFlagBits :: enum u8 {
	PreferHost,
	HostWrite,
	HostRead,
	Mapped,
	Dedicated,
	SharingModeConcurrent, // Defaults to exclusive
}
BufferDescFlags :: distinct bit_set[BufferDescFlagBits;u8]


//---------------------------------------------------------------------------//

BufferUsageFlagBits :: enum u8 {
	TransferSrc,
	TransferDst,
	UniformBuffer,
	IndexBuffer,
	VertexBuffer,
	Storagebuffer,
}

BufferUsageFlags :: distinct bit_set[BufferUsageFlagBits;u8]

//---------------------------------------------------------------------------//

BufferDesc :: struct {
	name:  common.Name,
	size:  u32,
	flags: BufferDescFlags,
	usage: BufferUsageFlags,
}

//---------------------------------------------------------------------------//

BufferResource :: struct {
	using backend_buffer: BackendBufferResource,
	desc:                 BufferDesc,
	mapped_ptr:           ^u8,
}

//---------------------------------------------------------------------------//

BufferRef :: Ref(BufferResource)

//---------------------------------------------------------------------------//

InvalidBufferRef := BufferRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_BUFFER_REF_ARRAY: RefArray(BufferResource)

//---------------------------------------------------------------------------//

@(private)
init_buffers :: proc() {
	G_BUFFER_REF_ARRAY = create_ref_array(BufferResource, MAX_BUFFERS)
	backend_init_buffers()
}

//---------------------------------------------------------------------------//

allocate_buffer_ref :: proc(p_name: common.Name) -> BufferRef {
	ref := BufferRef(create_ref(BufferResource, &G_BUFFER_REF_ARRAY, p_name))
	get_buffer(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_buffer :: proc(p_ref: BufferRef) -> bool {
	buffer := get_buffer(p_ref)

	if backend_create_buffer(p_ref, buffer) == false {
		free_ref(BufferResource, &G_BUFFER_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_buffer :: proc(p_ref: BufferRef) -> ^BufferResource {
	return get_resource(BufferResource, &G_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_buffer :: proc(p_ref: BufferRef) {
	buffer := get_buffer(p_ref)
	buffer.mapped_ptr = nil
	backend_destroy_buffer(buffer)
	free_ref(BufferResource, &G_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

map_buffer :: proc(p_ref: BufferRef) -> rawptr {
	buffer := get_buffer(p_ref)
	return backend_map_buffer(buffer)
}

//---------------------------------------------------------------------------//

unmap_buffer :: proc(p_ref: BufferRef) {
	buffer := get_buffer(p_ref)
	backend_unmap_buffer(buffer)
}

//---------------------------------------------------------------------------//

StagedBufferDesc :: struct {
	size:   u32,
	usage:  BufferUsageFlagBits,
	// stages in which the buffer is going to be read,
	// used to determine barrier placement
	stages: PipelineStageFlags,
}

//---------------------------------------------------------------------------//
