package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"
	import vma "../third_party/vma"
	import "../common"

	//---------------------------------------------------------------------------//

	BackendBufferResource :: struct {
		vk_buffer:  vk.Buffer,
		allocation: vma.Allocation,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_BUFFER_USAGE_MAPPING := map[BufferUsageFlagBits]vk.BufferUsageFlag {
		.TransferSrc   = .TRANSFER_SRC,
		.TransferDst   = .TRANSFER_DST,
		.UniformBuffer = .UNIFORM_BUFFER,
		.IndexBuffer   = .INDEX_BUFFER,
		.VertexBuffer  = .VERTEX_BUFFER,
		.Storagebuffer = .STORAGE_BUFFER,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_buffers :: proc() {

	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_buffer :: proc(
		p_name: common.Name,
		p_buffer_desc: BufferDesc,
		p_buffer: ^BufferResource,
	) -> bool {

		vk_usage: vk.BufferUsageFlags
		for usage in BufferUsageFlagBits {
			if usage in p_buffer_desc.usage {
				vk_usage += {G_BUFFER_USAGE_MAPPING[usage]}
			}
		}

		buffer_create_info := vk.BufferCreateInfo {
			sType       = .BUFFER_CREATE_INFO,
			size        = vk.DeviceSize(p_buffer_desc.size),
			usage       = vk_usage,
			sharingMode = .EXCLUSIVE,
		}

		alloc_usage: vma.MemoryUsage = .AUTO
		if .PreferHost in p_buffer_desc.flags {
			alloc_usage = .AUTO_PREFER_HOST
		}

		alloc_flags: vma.AllocationCreateFlags

		if .HostWrite in p_buffer_desc.flags {
			alloc_flags += {.HOST_ACCESS_SEQUENTIAL_WRITE}
		} else if .HostRead in p_buffer_desc.flags {
			alloc_flags += {.HOST_ACCESS_RANDOM}
		}

		if .Mapped in p_buffer_desc.flags {
			alloc_flags += {.CREATE_MAPPED}
		}

		if .Dedicated in p_buffer_desc.flags {
			alloc_flags += {.DEDICATED_MEMORY}
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = alloc_usage,
			flags = alloc_flags,
		}

		alloc_info := vma.AllocationInfo{}

		if res := vma.create_buffer(
			   G_RENDERER.vma_allocator,
			   &buffer_create_info,
			   &alloc_create_info,
			   &p_buffer.vk_buffer,
			   &p_buffer.allocation,
			   &alloc_info,
		   ); res != .SUCCESS {
			log.warnf("Failed to create buffer %s", res)
			return false
		}

		if .Mapped in p_buffer_desc.flags {
			p_buffer.mapped_ptr = cast(^u8)alloc_info.pMappedData
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_buffer :: proc(p_buffer: ^BufferResource) {
		vma.destroy_buffer(G_RENDERER.vma_allocator, p_buffer.vk_buffer, p_buffer.allocation)
	}

	//---------------------------------------------------------------------------//
}
