package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:log"
import "../common"

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
	size:  u32,
	usage: BufferUsageFlagBits,
	// stages in which the buffer is going to be read,
	// used to determine barrier placement
	stages: PipelineStageFlags,
}

//---------------------------------------------------------------------------//

StagedBuffer :: struct {
	device_buffer_ref:  BufferRef,
	staging_buffer_ref: BufferRef,
}

//---------------------------------------------------------------------------//

create_staged_buffer :: proc(p_name: common.Name, p_buffer_desc: StagedBufferDesc) -> (
	StagedBuffer,
	bool,
) {
	assert(p_buffer_desc.usage > .TransferDst)

	staging_buffer_desc := BufferDesc {
		size = p_buffer_desc.size,
		usage = {.TransferSrc},
		flags = {.HostWrite},
	}

	staging_buffer_ref := create_buffer(p_name, staging_buffer_desc)

	if staging_buffer_ref == InvalidBufferRef {
		log.debugf(
			"Failed to create staging buffer when creating buffer %s",
			common.get_string(p_name),
		)
		return {}, false
	}

	device_buffer_desc := BufferDesc {
		size = p_buffer_desc.size,
		usage = {p_buffer_desc.usage, .TransferDst},
		flags = {.Dedicated},
	}

	device_buffer_ref := create_buffer(p_name, device_buffer_desc)
	if device_buffer_ref == InvalidBufferRef {
		destroy_buffer(staging_buffer_ref)
		log.debugf(
			"Failed to create staging buffer when creating buffer %s",
			common.get_string(p_name),
		)
		return {}, false
	}
	
	return StagedBuffer {
		staging_buffer_ref = staging_buffer_ref,
		device_buffer_ref = device_buffer_ref,
	}, true
}

//---------------------------------------------------------------------------//

destroy_staged_buffer :: proc(p_staged_buffer: StagedBuffer) {
	destroy_buffer(p_staged_buffer.staging_buffer_ref)
	destroy_buffer(p_staged_buffer.device_buffer_ref)
}

//---------------------------------------------------------------------------//

update_staged_buffer :: proc(p_staged_buffer: StagedBuffer, p_data: []u8) {
	staging_buffer := get_buffer(p_staged_buffer.staging_buffer_ref)
	device_buffer := get_buffer(p_staged_buffer.device_buffer_ref)
	backend_update_staged_buffer(staging_buffer, device_buffer)
}

//---------------------------------------------------------------------------//
