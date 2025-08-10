package renderer

//---------------------------------------------------------------------------//

import "../common"
import vma "../third_party/vma"
import "core:c"
import vk "vendor:vulkan"

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
	DynamicUniformBuffer,
	IndexBuffer,
	VertexBuffer,
	StorageBuffer,
	DynamicStorageBuffer,
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

BufferAccessType :: enum u8 {
	None,
	Read,
	Write,
}

//---------------------------------------------------------------------------//

BufferResource :: struct {
	desc:        BufferDesc,
	mapped_ptr:  ^u8,
	// Virtual block used to suballocate the buffer using the VMA virtual allocator
	vma_block:   vma.VirtualBlock,
	queue:       DeviceQueueType,
	last_access: BufferAccessType,
}

//---------------------------------------------------------------------------//

BufferRef :: common.Ref(BufferResource)

//---------------------------------------------------------------------------//

InvalidBufferRef := BufferRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_BUFFER_REF_ARRAY: common.RefArray(BufferResource)

//---------------------------------------------------------------------------//

BufferSuballocation :: struct {
	offset:         u32,
	vma_allocation: vma.VirtualAllocation,
}

//---------------------------------------------------------------------------//

BufferSection :: struct {
	buffer_ref: BufferRef,
	offset:     u32,
	size:     u32,
}

InvalidBufferSection :: BufferSection {
	buffer_ref = {ref = c.UINT32_MAX},
}

//---------------------------------------------------------------------------//

@(private)
buffer_init :: proc() {
	G_BUFFER_REF_ARRAY = common.ref_array_create(
		BufferResource,
		MAX_BUFFERS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.buffers = make_soa(
		#soa[]BufferResource,
		MAX_BUFFERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_buffers = make_soa(
		#soa[]BackendBufferResource,
		MAX_BUFFERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	backend_buffer_init()
}

//---------------------------------------------------------------------------//

buffer_allocate :: proc(p_name: common.Name) -> BufferRef {
	ref := BufferRef(common.ref_create(BufferResource, &G_BUFFER_REF_ARRAY, p_name))
	g_resources.buffers[buffer_get_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

buffer_create :: proc(p_ref: BufferRef) -> bool {
	buffer := &g_resources.buffers[buffer_get_idx(p_ref)]

	// Create the virtual VMA block used for sub-allocations
	{
		virtual_block_create_info := vma.VirtualBlockCreateInfo {
			size  = vk.DeviceSize(buffer.desc.size),
			flags = {.LINEAR},
		}

		res := vma.create_virtual_block(&virtual_block_create_info, &buffer.vma_block)
		if res != .SUCCESS {
			return false
		}
	}

	if backend_buffer_create(p_ref) == false {
		common.ref_free(&G_BUFFER_REF_ARRAY, p_ref)
		return false
	}

	buffer.last_access = .None
	buffer.queue = .Graphics

	return true
}

//---------------------------------------------------------------------------//

buffer_get_idx :: #force_inline proc(p_ref: BufferRef) -> u32 {
	return common.ref_get_idx(&G_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

buffer_destroy :: proc(p_ref: BufferRef) {
	buffer := &g_resources.buffers[buffer_get_idx(p_ref)]
	buffer.mapped_ptr = nil
	backend_buffer_destroy(p_ref)
	common.ref_free(&G_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

buffer_mmap :: proc(p_ref: BufferRef) -> rawptr {
	return backend_buffer_mmap(p_ref)
}

//---------------------------------------------------------------------------//

buffer_unmmap :: proc(p_ref: BufferRef) {
	backend_buffer_unmmap(p_ref)
}

//---------------------------------------------------------------------------//

buffer_suballocate :: proc(p_buffer_ref: BufferRef, p_size: u32) -> (bool, BufferSuballocation) {
	buffer := &g_resources.buffers[buffer_get_idx(p_buffer_ref)]

	alloc_info := vma.VirtualAllocationCreateInfo {
		size  = vk.DeviceSize(p_size),
		flags = {.MIN_OFFSET, .MIN_MEMORY},
	}

	suballocation := BufferSuballocation{}
	suballocation_offset: vk.DeviceSize

	res := vma.virtual_allocate(
		buffer.vma_block,
		&alloc_info,
		&suballocation.vma_allocation,
		&suballocation_offset,
	)

	suballocation.offset = u32(suballocation_offset)

	return res == .SUCCESS, suballocation
}

//---------------------------------------------------------------------------//

buffer_free :: proc(p_buffer_ref: BufferRef, p_allocation: vma.VirtualAllocation) {
	buffer := &g_resources.buffers[buffer_get_idx(p_buffer_ref)]
	vma.virtual_free(buffer.vma_block, p_allocation)
}
//---------------------------------------------------------------------------//


buffer_free_all :: proc(p_buffer_ref: BufferRef) {
	buffer := &g_resources.buffers[buffer_get_idx(p_buffer_ref)]

	vma.destroy_virtual_block(buffer.vma_block)
	virtual_block_create_info := vma.VirtualBlockCreateInfo {
		size  = vk.DeviceSize(buffer.desc.size),
		flags = {.LINEAR},
	}

	res := vma.create_virtual_block(&virtual_block_create_info, &buffer.vma_block)
	assert(res == .SUCCESS)
}

//---------------------------------------------------------------------------//

buffer_find :: proc {
	buffer_find_by_name,
	buffer_find_by_str,
}

//---------------------------------------------------------------------------//

buffer_find_by_name :: proc(p_name: common.Name) -> BufferRef {
	ref := common.ref_find_by_name(&G_BUFFER_REF_ARRAY, p_name)
	if ref == InvalidBufferRef {
		return InvalidBufferRef
	}
	return BufferRef(ref)
}

//--------------------------------------------------------------------------//

buffer_find_by_str :: proc(p_str: string) -> BufferRef {
	return buffer_find_by_name(common.create_name(p_str))
}

//--------------------------------------------------------------------------//
