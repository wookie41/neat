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
	backend_create_buffer :: proc(p_buffer_ref: BufferRef) -> bool {

		image_idx := get_buffer_idx(p_buffer_ref)
		buffer := &g_resources.buffers[image_idx]
		backend_buffer := &g_resources.backend_buffers[image_idx]

		backend_buffer.owning_queue_family_idx = G_RENDERER.queue_family_graphics_index

		vk_usage: vk.BufferUsageFlags
		for usage in BufferUsageFlagBits {
			if usage in buffer.desc.usage {
				vk_usage += {G_BUFFER_USAGE_MAPPING[usage]}
			}
		}

		if .UniformBuffer in buffer.desc.usage || .DynamicUniformBuffer in buffer.desc.usage {
			buffer.desc.size +=
				(buffer.desc.size %
					u32(G_RENDERER.device_properties.limits.minUniformBufferOffsetAlignment))
		}

		buffer_create_info := vk.BufferCreateInfo {
			sType       = .BUFFER_CREATE_INFO,
			size        = vk.DeviceSize(buffer.desc.size),
			usage       = vk_usage,
			sharingMode = .EXCLUSIVE,
		}

		alloc_usage: vma.MemoryUsage = .AUTO
		if .PreferHost in buffer.desc.flags {
			alloc_usage = .AUTO_PREFER_HOST
		}

		alloc_flags: vma.AllocationCreateFlags

		has_mapped_ptr := false
		if .IntegratedGPU in G_RENDERER.gpu_device_flags && .TRANSFER_DST in vk_usage {
			alloc_flags += {.CREATE_MAPPED}
			alloc_flags += {.HOST_ACCESS_SEQUENTIAL_WRITE}
			has_mapped_ptr = true
		}
		if .Mapped in buffer.desc.flags {
			alloc_flags += {.CREATE_MAPPED, .HOST_ACCESS_SEQUENTIAL_WRITE}
			has_mapped_ptr = true
		}

		if .HostWrite in buffer.desc.flags {
			alloc_flags += {.HOST_ACCESS_SEQUENTIAL_WRITE}
		} else if .HostRead in buffer.desc.flags {
			alloc_flags += {.HOST_ACCESS_RANDOM}
		}

		if .Dedicated in buffer.desc.flags {
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
			&backend_buffer.vk_buffer,
			&backend_buffer.allocation,
			&alloc_info,
		); res != .SUCCESS {
			log.warnf("Failed to create buffer %s", res)
			return false
		}

		if has_mapped_ptr {
			assert(alloc_info.pMappedData != nil)
			buffer.mapped_ptr = cast(^u8)alloc_info.pMappedData
		}

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		vk_name := strings.clone_to_cstring(
			common.get_string(buffer.desc.name),
			temp_arena.allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(backend_buffer.vk_buffer),
			objectType   = .BUFFER,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_buffer :: proc(p_buffer_ref: BufferRef) {
		backend_buffer := &g_resources.backend_buffers[get_buffer_idx(p_buffer_ref)]
		vma.destroy_buffer(
			G_RENDERER.vma_allocator,
			backend_buffer.vk_buffer,
			backend_buffer.allocation,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_map_buffer :: proc(p_buffer_ref: BufferRef) -> rawptr {
		mapped_ptr: rawptr
		backend_buffer := &g_resources.backend_buffers[get_buffer_idx(p_buffer_ref)]
		vma.map_memory(G_RENDERER.vma_allocator, backend_buffer.allocation, &mapped_ptr)
		return mapped_ptr
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_unmap_buffer :: proc(p_buffer_ref: BufferRef) {
		backend_buffer := &g_resources.backend_buffers[get_buffer_idx(p_buffer_ref)]
		vma.unmap_memory(G_RENDERER.vma_allocator, backend_buffer.allocation)
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
