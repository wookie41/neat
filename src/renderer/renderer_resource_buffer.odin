package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "../common"

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

BufferDescFlagBits :: enum u8 {
	PreferHost,
	HostWrite,
	HostRead,
	Mapped,
	Dedicated,
}
BufferDescFlags :: distinct bit_set[BufferDescFlagBits;u8]

//---------------------------------------------------------------------------//

BufferDesc :: struct {
	size:  u32,
	flags: BufferDescFlags,
	usage: BufferUsageFlags,
}

//---------------------------------------------------------------------------//

create_buffer :: proc(p_name: common.Name, p_buffer_desc: BufferDesc) -> BufferRef {
	ref := BufferRef(create_ref(BufferResource, &G_BUFFER_REF_ARRAY, p_name))
	idx := get_ref_idx(ref)
	buffer := &G_BUFFER_REF_ARRAY.resource_array[idx]

	buffer.desc = p_buffer_desc

	if backend_create_buffer(p_name, p_buffer_desc, buffer) == false {
		free_ref(BufferResource, &G_BUFFER_REF_ARRAY, ref)
        return InvalidBufferRef
	}

	return ref
}

//---------------------------------------------------------------------------//

get_buffer :: proc(p_ref: BufferRef) -> ^BufferResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_BUFFER_REF_ARRAY.resource_array)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_BUFFER_REF_ARRAY.generations[idx])

	return &G_BUFFER_REF_ARRAY.resource_array[idx]
}

//---------------------------------------------------------------------------//
