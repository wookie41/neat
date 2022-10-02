package renderer

//---------------------------------------------------------------------------//

import vk "vendor:vulkan"


//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_pool: vk.DescriptorPool,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupResource :: struct {}

	//---------------------------------------------------------------------------//

	backend_init_bind_groups :: proc() {

		// Create descriptor pools
		{
			pool_sizes := []vk.DescriptorPoolSize{
				{type = .SAMPLER, descriptorCount = 1 << 15},
				{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1 << 15},
				{type = .SAMPLED_IMAGE, descriptorCount = 1 << 15},
				{type = .STORAGE_IMAGE, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER, descriptorCount = 1 << 15},
				{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER, descriptorCount = 1 << 15},
				{type = .STORAGE_BUFFER_DYNAMIC, descriptorCount = 1 << 15},
			}

			descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
				sType         = .DESCRIPTOR_POOL_CREATE_INFO,
				maxSets       = 1 << 15,
				poolSizeCount = u32(len(pool_sizes)),
				pPoolSizes    = raw_data(pool_sizes),
			}

			vk.CreateDescriptorPool(
				G_RENDERER.device,
				&descriptor_pool_create_info,
				nil,
				&descriptor_pool.descriptor_pool,
			)
		}
	}

    //---------------------------------------------------------------------------//

	backend_create_bind_group :: proc(p_ref: BindGroupRef, p_bind_group: BindGroupDesc) {

	}

	//---------------------------------------------------------------------------//
}
