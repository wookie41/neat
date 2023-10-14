
package renderer
//---------------------------------------------------------------------------//

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

	INTERNAL: struct {
		immutable_samplers:          []vk.Sampler,
		descriptor_set_layout_cache: map[u32]DescriptorSetLayoutCacheEntry,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupLayoutResource :: struct {
		vk_descriptor_set_layout: vk.DescriptorSetLayout,
	}

	@(private)
	backend_init_bind_group_layouts :: proc() -> bool {

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
				borderColor  = .INT_OPAQUE_BLACK,
				compareOp    = .ALWAYS,
				mipmapMode   = .LINEAR,
			}

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[0],
			)

			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[1],
			)

			sampler_create_info.addressModeU = .REPEAT
			sampler_create_info.addressModeV = .REPEAT
			sampler_create_info.addressModeW = .REPEAT

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[2],
			)

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

			sampler_create_info.addressModeU = .CLAMP_TO_BORDER
			sampler_create_info.addressModeV = .CLAMP_TO_BORDER
			sampler_create_info.addressModeW = .CLAMP_TO_BORDER

			vk.CreateSampler(
				G_RENDERER.device,
				&sampler_create_info,
				nil,
				&INTERNAL.immutable_samplers[4],
			)

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

	backend_create_bind_group_layout :: proc(
		p_bind_group_layout_ref: BindGroupLayoutRef,
		p_bind_group_layout: ^BindGroupLayoutResource,
	) -> bool {

		// First check the cache, maybe we can reuse an existing descriptor layout layout
		if p_bind_group_layout.hash in INTERNAL.descriptor_set_layout_cache {

			hash_entry := &INTERNAL.descriptor_set_layout_cache[p_bind_group_layout.hash]
			hash_entry.ref_count += 1

			p_bind_group_layout.vk_descriptor_set_layout = hash_entry.descriptor_set_layout
			return true
		}

		// Create a new descriptor set layout
		descriptor_set_layout_bindings := make(
			[]vk.DescriptorSetLayoutBinding,
			u32(len(p_bind_group_layout.desc.bindings)),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(descriptor_set_layout_bindings, G_RENDERER_ALLOCATORS.temp_allocator)

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = u32(len(descriptor_set_layout_bindings)),
			pBindings    = raw_data(descriptor_set_layout_bindings),
		}

		for i in 0 ..< create_info.bindingCount {
			bind_group_binding := &p_bind_group_layout.desc.bindings[i]
			descriptor_binding := &descriptor_set_layout_bindings[i]

			descriptor_binding^ = vk.DescriptorSetLayoutBinding {
				binding            = i,
				descriptorCount    = bind_group_binding.count,
				pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
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
		}

		if vk.CreateDescriptorSetLayout(
			   G_RENDERER.device,
			   &create_info,
			   nil,
			   &p_bind_group_layout.vk_descriptor_set_layout,
		   ) !=
		   .SUCCESS {
			return false
		}

		// Cache this descriptor set layout
		INTERNAL.descriptor_set_layout_cache[p_bind_group_layout.hash] =
			DescriptorSetLayoutCacheEntry {
				ref_count             = 1,
				descriptor_set_layout = p_bind_group_layout.vk_descriptor_set_layout,
			}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_bind_group_layout :: proc(p_bind_group_ref: BindGroupLayoutRef) {
		bind_group_layout := get_bind_group_layout(p_bind_group_ref)
		cache_entry := &INTERNAL.descriptor_set_layout_cache[bind_group_layout.hash]
		cache_entry.ref_count -= 1

		if cache_entry.ref_count == 0 {
			vk.DestroyDescriptorSetLayout(
				G_RENDERER.device,
				bind_group_layout.vk_descriptor_set_layout,
				nil,
			)
			delete_key(&INTERNAL.descriptor_set_layout_cache, bind_group_layout.hash)
		}
	}

	//---------------------------------------------------------------------------//

}
