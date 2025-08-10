package renderer

//---------------------------------------------------------------------------//

import "../common"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_pool: vk.DescriptorPool,
	}

	//---------------------------------------------------------------------------//

	BackendBindGroupResource :: struct {
		vk_descriptor_set: vk.DescriptorSet,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_init :: proc() -> bool {
		// Create descriptor pools
		{
			pool_sizes := []vk.DescriptorPoolSize {
				{type = .SAMPLER, descriptorCount = len(SamplerType)},
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
				flags         = {.UPDATE_AFTER_BIND}, // @TODO create a separate pool for that 
			}

			vk.CreateDescriptorPool(
				G_RENDERER.device,
				&descriptor_pool_create_info,
				nil,
				&INTERNAL.descriptor_pool,
			)
		}
		return true
	}

	//---------------------------------------------------------------------------//

	backend_bind_group_create :: proc(p_bind_group_ref: BindGroupRef) -> bool {

		bind_group_idx := bind_group_get_idx(p_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		backend_bind_group_layout := &g_resources.backend_bind_group_layouts[bind_group_layout_get_idx(bind_group.desc.layout_ref)]

		descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			pSetLayouts        = &backend_bind_group_layout.vk_descriptor_set_layout,
			descriptorSetCount = 1,
			descriptorPool     = INTERNAL.descriptor_pool,
		}

		return(
			vk.AllocateDescriptorSets(
				G_RENDERER.device,
				&descriptor_set_alloc_info,
				&backend_bind_group.vk_descriptor_set,
			) ==
			.SUCCESS \
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_bind_graphics :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_pipeline_ref: GraphicsPipelineRef,
		p_bind_group_ref: BindGroupRef,
		p_target: u32,
		p_dynamic_offsets: []u32,
	) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(p_cmd_buff_ref)]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_get_idx(p_bind_group_ref)]

		pipeline_idx := graphics_pipeline_get_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_graphics_pipelines[pipeline_idx]

		vk.CmdBindDescriptorSets(
			backend_cmd_buffer.vk_cmd_buff,
			.GRAPHICS,
			backend_pipeline.vk_pipeline_layout,
			p_target,
			1,
			&backend_bind_group.vk_descriptor_set,
			u32(len(p_dynamic_offsets)),
			raw_data(p_dynamic_offsets),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_bind_compute :: proc(
		p_cmd_buff_ref: CommandBufferRef,
		p_pipeline_ref: ComputePipelineRef,
		p_bind_group_ref: BindGroupRef,
		p_target: u32,
		p_dynamic_offsets: []u32,
	) {
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(p_cmd_buff_ref)]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_get_idx(p_bind_group_ref)]

		pipeline_idx := compute_pipeline_get_idx(p_pipeline_ref)
		backend_pipeline := &g_resources.backend_compute_pipelines[pipeline_idx]

		vk.CmdBindDescriptorSets(
			backend_cmd_buffer.vk_cmd_buff,
			.COMPUTE,
			backend_pipeline.vk_pipeline_layout,
			p_target,
			1,
			&backend_bind_group.vk_descriptor_set,
			u32(len(p_dynamic_offsets)),
			raw_data(p_dynamic_offsets),
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_destroy :: proc(p_bind_group_ref: BindGroupRef) {
		bind_group_idx := bind_group_get_idx(p_bind_group_ref)
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		descriptor_set_to_delete := defer_resource_delete(
			safe_destroy_descriptor_set,
			vk.DescriptorSet,
		)
		descriptor_set_to_delete^ = backend_bind_group.vk_descriptor_set
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_update :: proc(
		p_bind_group_ref: BindGroupRef,
		p_bind_group_update: BindGroupUpdate,
	) {

		bind_group_idx := bind_group_get_idx(p_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		// Allocate descriptor write array (for now we just write the entire bind group, no dirty bindings checking)
		buffer_infos_count := len(p_bind_group_update.buffers)

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		descriptor_writes := make(
			[dynamic]vk.WriteDescriptorSet,
			temp_arena.allocator,
		)

		image_writes := make(
			[dynamic]vk.DescriptorImageInfo,
			temp_arena.allocator,
		)
		buffer_writes := make([]vk.DescriptorBufferInfo, buffer_infos_count, temp_arena.allocator)

		bind_group_layout_idx := bind_group_layout_get_idx(bind_group.desc.layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		for image_binding in p_bind_group_update.images {

			binding := bind_group_layout.desc.bindings[image_binding.binding]
			assert(
				binding.type == .Image || binding.type == .StorageImage,
				"Image binding required",
			)

			image := &g_resources.images[image_get_idx(image_binding.image_ref)]
			backend_image := &g_resources.backend_images[image_get_idx(image_binding.image_ref)]

			image_info := vk.DescriptorImageInfo{}

			if binding.type == .StorageImage {
				image_info.imageLayout = .GENERAL
			} else if image.desc.format > .DepthStencilFormatsStart &&
			   image.desc.format < .DepthStencilFormatsEnd {
				image_info.imageLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL
			} else if image.desc.format > .DepthFormatsStart &&
			   image.desc.format < .DepthFormatsEnd {
				image_info.imageLayout = .DEPTH_READ_ONLY_OPTIMAL
			} else {
				image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
			}


			if binding.type == .StorageImage {

				base_image_write_idx := len(image_writes)

				for mip in image_binding.base_mip ..< image_binding.mip_count {
					image_info.imageView = backend_image.vk_views[image_binding.base_array][mip]
					append(&image_writes, image_info)
				}

				// Bind each mip as a seperate storage image
				descriptor_write := vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = image_binding.mip_count,
					dstBinding      = image_binding.binding,
					dstSet          = backend_bind_group.vk_descriptor_set,
					pImageInfo      = &image_writes[base_image_write_idx],
					descriptorType  = .STORAGE_IMAGE,
				}

				append(&descriptor_writes, descriptor_write)

				continue
			}

			for array_layer in image_binding.base_array ..< image_binding.layer_count {

				image_write_idx := len(image_writes)
				image_info.imageView = backend_image.vk_all_mips_views[array_layer]
				append(&image_writes, image_info)

				descriptor_write := vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					dstBinding      = image_binding.binding,
					dstSet          = backend_bind_group.vk_descriptor_set,
					pImageInfo      = &image_writes[image_write_idx],
					dstArrayElement = array_layer,
					descriptorType  = .SAMPLED_IMAGE,
				}

				append(&descriptor_writes, descriptor_write)
			}
		}

		for buffer_binding, i in p_bind_group_update.buffers {

			binding := bind_group_layout.desc.bindings[buffer_binding.binding]
			assert(
				binding.type == .StorageBuffer ||
				binding.type == .StorageBufferDynamic ||
				binding.type == .UniformBuffer ||
				binding.type == .UniformBufferDynamic,
				"Buffer binding required",
			)

			binding_buffer_idx := buffer_get_idx(buffer_binding.buffer_ref)
			buffer := &g_resources.buffers[binding_buffer_idx]
			backend_buffer := &g_resources.backend_buffers[binding_buffer_idx]

			buffer_writes[i].buffer = backend_buffer.vk_buffer
			buffer_writes[i].offset = vk.DeviceSize(buffer_binding.offset)
			buffer_writes[i].range = vk.DeviceSize(buffer_binding.size)

			descriptor_write := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				descriptorCount = 1,
				dstBinding      = buffer_binding.binding,
				dstSet          = backend_bind_group.vk_descriptor_set,
				pBufferInfo     = &buffer_writes[i],
				dstArrayElement = buffer_binding.array_index,
			}

			if .UniformBuffer in buffer.desc.usage {
				descriptor_write.descriptorType = .UNIFORM_BUFFER
			} else if .DynamicUniformBuffer in buffer.desc.usage {
				descriptor_write.descriptorType = .UNIFORM_BUFFER_DYNAMIC
			} else if .StorageBuffer in buffer.desc.usage {
				descriptor_write.descriptorType = .STORAGE_BUFFER
			} else if .DynamicStorageBuffer in buffer.desc.usage {
				descriptor_write.descriptorType = .STORAGE_BUFFER_DYNAMIC
			} else {
				assert(false, "Invalid buffer binding")
			}

			append(&descriptor_writes, descriptor_write)

		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(len(descriptor_writes)),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	is_buffer_binding :: #force_inline proc(p_binding_type: BindGroupLayoutBindingType) -> bool {
		return(
			p_binding_type == .UniformBuffer ||
			p_binding_type == .UniformBufferDynamic ||
			p_binding_type == .StorageBuffer ||
			p_binding_type == .StorageBufferDynamic \
		)
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	is_image_binding :: #force_inline proc(p_binding_type: BindGroupLayoutBindingType) -> bool {
		return p_binding_type == .Image || p_binding_type == .StorageImage
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	safe_destroy_descriptor_set :: proc(p_user_data: rawptr) {
		descriptor_set := (^vk.DescriptorSet)(p_user_data)

		vk.FreeDescriptorSets(G_RENDERER.device, INTERNAL.descriptor_pool, 1, descriptor_set)
	}

	//---------------------------------------------------------------------------//
}
