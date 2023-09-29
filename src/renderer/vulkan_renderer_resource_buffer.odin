package renderer

//---------------------------------------------------------------------------//

import "../common"
import vma "../third_party/vma"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {


	//---------------------------------------------------------------------------//

	BackendBufferResource :: struct {
		vk_buffer:               vk.Buffer,
		allocation:              vma.Allocation,
		owning_queue_family_idx: u32,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_BUFFER_USAGE_MAPPING := map[BufferUsageFlagBits]vk.BufferUsageFlag {
		.TransferSrc          = .TRANSFER_SRC,
		.TransferDst          = .TRANSFER_DST,
		.UniformBuffer        = .UNIFORM_BUFFER,
		.DynamicUniformBuffer = .UNIFORM_BUFFER,
		.IndexBuffer          = .INDEX_BUFFER,
		.VertexBuffer         = .VERTEX_BUFFER,
		.StorageBuffer        = .STORAGE_BUFFER,
		.DynamicStorageBuffer = .STORAGE_BUFFER,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_buffers :: proc() {

	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_buffer :: proc(p_buffer_ref: BufferRef, p_buffer: ^BufferResource) -> bool {
		p_buffer.owning_queue_family_idx = vk.QUEUE_FAMILY_IGNORED

		vk_usage: vk.BufferUsageFlags
		for usage in BufferUsageFlagBits {
			if usage in p_buffer.desc.usage {
				vk_usage += {G_BUFFER_USAGE_MAPPING[usage]}
			}
		}

		buffer_create_info := vk.BufferCreateInfo {
			sType       = .BUFFER_CREATE_INFO,
			size        = vk.DeviceSize(p_buffer.desc.size),
			usage       = vk_usage,
			sharingMode = .EXCLUSIVE,
		}

		alloc_usage: vma.MemoryUsage = .AUTO
		if .PreferHost in p_buffer.desc.flags {
			alloc_usage = .AUTO_PREFER_HOST
		}

		alloc_flags: vma.AllocationCreateFlags

		has_mapped_ptr := false
		if .IntegratedGPU in G_RENDERER.gpu_device_flags && .TRANSFER_DST in vk_usage {
			alloc_flags += {.CREATE_MAPPED}
			alloc_flags += {.HOST_ACCESS_SEQUENTIAL_WRITE}
			has_mapped_ptr = true
		}
		if .Mapped in p_buffer.desc.flags {
			alloc_flags += {.CREATE_MAPPED}
			has_mapped_ptr = true
		}

		if .HostWrite in p_buffer.desc.flags {
			alloc_flags += {.HOST_ACCESS_SEQUENTIAL_WRITE}
		} else if .HostRead in p_buffer.desc.flags {
			alloc_flags += {.HOST_ACCESS_RANDOM}
		}

		if .Dedicated in p_buffer.desc.flags {
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

		if has_mapped_ptr {
			assert(alloc_info.pMappedData != nil)
			p_buffer.mapped_ptr = cast(^u8)alloc_info.pMappedData
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(p_buffer.desc.name),
			G_RENDERER_ALLOCATORS.names_allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(p_buffer.vk_buffer),
			objectType   = .BUFFER,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_buffer :: proc(p_buffer: ^BufferResource) {
		vma.destroy_buffer(G_RENDERER.vma_allocator, p_buffer.vk_buffer, p_buffer.allocation)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_map_buffer :: proc(p_buffer: ^BufferResource) -> rawptr {
		mapped_ptr: rawptr
		vma.map_memory(G_RENDERER.vma_allocator, p_buffer.allocation, &mapped_ptr)
		return mapped_ptr
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_unmap_buffer :: proc(p_buffer: ^BufferResource) {
		vma.unmap_memory(G_RENDERER.vma_allocator, p_buffer.allocation)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_update_staged_buffer :: proc(
		p_staging_buffer: ^BufferResource,
		p_device_buffer: ^BufferResource,
	) {
	}

	//---------------------------------------------------------------------------//

}
