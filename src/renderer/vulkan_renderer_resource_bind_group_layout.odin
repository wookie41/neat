
package renderer
//---------------------------------------------------------------------------//

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	DescriptorSetLayoutCacheEntry :: struct {
		ref_count:             u16,
		descriptor_set_layout: vk.DescriptorSetLayout,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		immutable_samplers:          []vk.Sampler,
		descriptor_set_layout_cache: map[u32]DescriptorSetLayoutCacheEntry,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupLayoutResource :: struct {
		vk_descriptor_set_layout: vk.DescriptorSetLayout,
	}

	@(private)
	backend_bind_group_layout_init :: proc() -> bool {

		// Init the descriptor layout cache
		INTERNAL.descriptor_set_layout_cache = make(
			map[u32]DescriptorSetLayoutCacheEntry,
			1024,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		// Create the immutable samplers
		{
			INTERNAL.immutable_samplers = make(
				[]vk.Sampler,
				len(SamplerType),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			sampler_create_info := vk.SamplerCreateInfo {
				sType        = .SAMPLER_CREATE_INFO,
				magFilter    = .NEAREST,
				minFilter    = .NEAREST,
				addressModeU = .CLAMP_TO_EDGE,
				addressModeW = .CLAMP_TO_EDGE,
				addressModeV = .CLAMP_TO_EDGE,
				// @TODO
				// anisotropyEnable = true,
				//maxAnisotropy    = device_properties.limits.maxSamplerAnisotropy,
				borderColor  = .FLOAT_OPAQUE_WHITE,
				compareOp    = .ALWAYS,
				mipmapMode   = .LINEAR,
				maxLod       = 16,
			}


			// Nearest, clamp to edge
			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[0],
			)

			// Nearest clamp to border
			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[1],
			)

			// Nearest, repeat
			sampler_create_info.addressModeU = .REPEAT
			sampler_create_info.addressModeV = .REPEAT
			sampler_create_info.addressModeW = .REPEAT

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[2],
			)

			// Linear clamp to edge
			sampler_create_info.magFilter = .LINEAR
			sampler_create_info.minFilter = .LINEAR

			sampler_create_info.addressModeU = .CLAMP_TO_EDGE
			sampler_create_info.addressModeV = .CLAMP_TO_EDGE
			sampler_create_info.addressModeW = .CLAMP_TO_EDGE

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[3],
			)

			// Linear clamp to border
			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[4],
			)


			// Linear repeat
			sampler_create_info.addressModeU = .REPEAT
			sampler_create_info.addressModeV = .REPEAT
			sampler_create_info.addressModeW = .REPEAT

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[5],
			)
		}

		return true
	}

	//---------------------------------------------------------------------------//

	backend_bind_group_layout_create :: proc(p_bind_group_layout_ref: BindGroupLayoutRef) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		bind_group_layout_idx := bind_group_layout_get_idx(p_bind_group_layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]
		backend_bind_group_layout := &g_resources.backend_bind_group_layouts[bind_group_layout_idx]

		binding_flags := make(
			[]vk.DescriptorBindingFlags,
			len(bind_group_layout.desc.bindings),
			temp_arena.allocator,
		)
		defer delete(binding_flags, temp_arena.allocator)

		flags_create_info := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
			sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
			bindingCount  = u32(len(binding_flags)),
			pBindingFlags = raw_data(binding_flags),
		}

		// First check the cache, maybe we can reuse an existing descriptor layout layout
		if bind_group_layout.hash in INTERNAL.descriptor_set_layout_cache {

			hash_entry := &INTERNAL.descriptor_set_layout_cache[bind_group_layout.hash]
			hash_entry.ref_count += 1

			backend_bind_group_layout.vk_descriptor_set_layout = hash_entry.descriptor_set_layout
			return true
		}

		// Create a new descriptor set layout
		descriptor_set_layout_bindings := make(
			[]vk.DescriptorSetLayoutBinding,
			u32(len(bind_group_layout.desc.bindings)),
			temp_arena.allocator,
		)

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = u32(len(descriptor_set_layout_bindings)),
			pBindings    = raw_data(descriptor_set_layout_bindings),
		}

		if .BindlessResources in bind_group_layout.desc.flags {
			create_info.flags += {.UPDATE_AFTER_BIND_POOL}
		}

		for i in 0 ..< create_info.bindingCount {
			bind_group_binding := &bind_group_layout.desc.bindings[i]
			descriptor_binding := &descriptor_set_layout_bindings[i]

			stage_flags := vk.ShaderStageFlags{}
			if .Vertex in bind_group_binding.shader_stages {
				stage_flags += {.VERTEX}
			}
			if .Pixel in bind_group_binding.shader_stages {
				stage_flags += {.FRAGMENT}
			}
			if .Compute in bind_group_binding.shader_stages {
				stage_flags += {.COMPUTE}
			}

			descriptor_binding^ = vk.DescriptorSetLayoutBinding {
				binding         = i,
				descriptorCount = bind_group_binding.count,
				stageFlags      = stage_flags,
			}

			if bind_group_binding.type == .Sampler {
				descriptor_binding.pImmutableSamplers =
				&INTERNAL.immutable_samplers[bind_group_binding.immutable_sampler_idx]
			}

			switch bind_group_binding.type {
			case .Image:
				descriptor_binding.descriptorType = .SAMPLED_IMAGE
			case .StorageImage:
				descriptor_binding.descriptorType = .STORAGE_IMAGE
			case .Sampler:
				descriptor_binding.descriptorType = .SAMPLER
			case .UniformBuffer:
				descriptor_binding.descriptorType = .UNIFORM_BUFFER
			case .UniformBufferDynamic:
				descriptor_binding.descriptorType = .UNIFORM_BUFFER_DYNAMIC
			case .StorageBuffer:
				descriptor_binding.descriptorType = .STORAGE_BUFFER
			case .StorageBufferDynamic:
				descriptor_binding.descriptorType = .STORAGE_BUFFER_DYNAMIC
			}

			// Add the Vulkan required flags for bindless image arrays
			// @TODO maybe add
			if .BindlessImageArray in bind_group_binding.flags {
				binding_flags[i] = {.UPDATE_AFTER_BIND, .PARTIALLY_BOUND}
			}
		}

		flags_create_info.pBindingFlags = raw_data(binding_flags)
		create_info.pNext = &flags_create_info

		if vk.CreateDescriptorSetLayout(
			   G_RENDERER.device,
			   &create_info,
			   nil,
			   &backend_bind_group_layout.vk_descriptor_set_layout,
		   ) !=
		   .SUCCESS {
			return false
		}

		// Cache this descriptor set layout
		INTERNAL.descriptor_set_layout_cache[bind_group_layout.hash] =
			DescriptorSetLayoutCacheEntry {
				ref_count             = 1,
				descriptor_set_layout = backend_bind_group_layout.vk_descriptor_set_layout,
			}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_layout_destroy :: proc(p_bind_group_ref: BindGroupLayoutRef) {
		bind_group_idx := bind_group_layout_get_idx(p_bind_group_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_idx]
		backend_bind_group_layout := &g_resources.backend_bind_group_layouts[bind_group_idx]

		cache_entry := &INTERNAL.descriptor_set_layout_cache[bind_group_layout.hash]
		cache_entry.ref_count -= 1

		if cache_entry.ref_count == 0 {
			delete_key(&INTERNAL.descriptor_set_layout_cache, bind_group_layout.hash)

			layout_to_delete := defer_resource_delete(
				safe_destroy_descriptor_set_layout,
				vk.DescriptorSetLayout,
			)
			layout_to_delete^ = backend_bind_group_layout.vk_descriptor_set_layout
		}
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	safe_destroy_descriptor_set_layout :: proc(p_user_data: rawptr) {
		set_layout := (^vk.DescriptorSetLayout)(p_user_data)

		vk.DestroyDescriptorSetLayout(G_RENDERER.device, set_layout^, nil)
	}

	//---------------------------------------------------------------------------//
}
