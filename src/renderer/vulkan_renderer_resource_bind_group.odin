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
	backend_init_bind_groups :: proc() -> bool {
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

	backend_create_bind_group :: proc(p_bind_group_ref: BindGroupRef) -> bool {

		bind_group_idx := get_bind_group_idx(p_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		backend_bind_group_layout := &g_resources.backend_bind_group_layouts[get_bind_group_layout_idx(bind_group.desc.layout_ref)]

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
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		backend_bind_group := &g_resources.backend_bind_groups[get_bind_group_idx(p_bind_group_ref)]

		pipeline_idx := get_graphics_pipeline_idx(p_pipeline_ref)
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
		backend_cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(p_cmd_buff_ref)]
		backend_bind_group := &g_resources.backend_bind_groups[get_bind_group_idx(p_bind_group_ref)]

		pipeline_idx := get_compute_pipeline_idx(p_pipeline_ref)
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
	backend_destroy_bind_group :: proc(p_bind_group_ref: BindGroupRef) {
		bind_group_idx := get_bind_group_idx(p_bind_group_ref)
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		descriptor_set_to_delete := defer_resource_delete(safe_destroy_descriptor_set, vk.DescriptorSet)
		descriptor_set_to_delete^ = backend_bind_group.vk_descriptor_set
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_group_update :: proc(
		p_bind_group_ref: BindGroupRef,
		p_bind_group_update: BindGroupUpdate,
	) {

		bind_group_idx := get_bind_group_idx(p_bind_group_ref)
		bind_group := &g_resources.bind_groups[bind_group_idx]
		backend_bind_group := &g_resources.backend_bind_groups[bind_group_idx]

		// Allocate descriptor write array (for now we just write the entire bind group, no dirty bindings checking)
		images_infos_count := len(p_bind_group_update.images)
		buffer_infos_count := len(p_bind_group_update.buffers)
		total_writes_count := buffer_infos_count + images_infos_count

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		descriptor_writes := make(
			[]vk.WriteDescriptorSet,
			total_writes_count,
			temp_arena.allocator,
		)

		image_writes := make([]vk.DescriptorImageInfo, images_infos_count, temp_arena.allocator)
		buffer_writes := make([]vk.DescriptorBufferInfo, buffer_infos_count, temp_arena.allocator)

		bind_group_layout_idx := get_bind_group_layout_idx(bind_group.desc.layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		for image_binding, i in p_bind_group_update.images {

			binding := bind_group_layout.desc.bindings[image_binding.binding]
			assert(binding.type == .Image || binding.type == .StorageImage, "Image binding required")

			image := &g_resources.images[get_image_idx(image_binding.image_ref)]
			backend_image := &g_resources.backend_images[get_image_idx(image_binding.image_ref)]

			if .AddressSubresource in image_binding.flags {

				if image_binding.mip_count > 1 {
					assert(image_binding.mip_count == image.desc.mip_count) // We don't support binding sub-ranges of mips as of now
					image_writes[i].imageView = backend_image.vk_all_mips_views[image_binding.base_array]
				} else {
					image_writes[i].imageView = backend_image.vk_views[image_binding.base_array][image_binding.base_mip]
				}

			} else {
				image_writes[i].imageView = backend_image.vk_image_view
			}

			if binding.type == .StorageImage {
				image_writes[i].imageLayout = .GENERAL	
			} else if image.desc.format > .DepthStencilFormatsStart && image.desc.format < .DepthStencilFormatsEnd {
				image_writes[i].imageLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL
			} else if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {
				image_writes[i].imageLayout = .DEPTH_READ_ONLY_OPTIMAL
			}else {
				image_writes[i].imageLayout = .SHADER_READ_ONLY_OPTIMAL		
			}			

			descriptor_writes[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				descriptorCount = 1,
				dstBinding      = image_binding.binding,
				dstSet          = backend_bind_group.vk_descriptor_set,
				pImageInfo      = &image_writes[i],
				dstArrayElement = image_binding.array_element,
			}

			if binding.type == .Image {
				descriptor_writes[i].descriptorType = .SAMPLED_IMAGE
			} else {
				descriptor_writes[i].descriptorType = .STORAGE_IMAGE
			}
		}

		for buffer_binding, i in p_bind_group_update.buffers {

			binding := bind_group_layout.desc.bindings[buffer_binding.binding]
			assert(
				binding.type == .StorageBuffer || 
				binding.type == .StorageBufferDynamic || 
				binding.type == .UniformBuffer ||
				binding.type == .UniformBufferDynamic, "Buffer binding required")

			binding_buffer_idx := get_buffer_idx(buffer_binding.buffer_ref)
			buffer := &g_resources.buffers[binding_buffer_idx]
			backend_buffer := &g_resources.backend_buffers[binding_buffer_idx]

			buffer_writes[i].buffer = backend_buffer.vk_buffer
			buffer_writes[i].offset = vk.DeviceSize(buffer_binding.offset)
			buffer_writes[i].range = vk.DeviceSize(buffer_binding.size)

			descriptor_writes[images_infos_count + i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				descriptorCount = 1,
				dstBinding      = buffer_binding.binding,
				dstSet          = backend_bind_group.vk_descriptor_set,
				pBufferInfo     = &buffer_writes[i],
				dstArrayElement = buffer_binding.array_index,
			}

			if .UniformBuffer in buffer.desc.usage {
				descriptor_writes[images_infos_count + i].descriptorType = .UNIFORM_BUFFER
			} else if .DynamicUniformBuffer in buffer.desc.usage {
				descriptor_writes[images_infos_count + i].descriptorType =
				.UNIFORM_BUFFER_DYNAMIC
			} else if .StorageBuffer in buffer.desc.usage {
				descriptor_writes[images_infos_count + i].descriptorType = .STORAGE_BUFFER
			} else if .DynamicStorageBuffer in buffer.desc.usage {
				descriptor_writes[images_infos_count + i].descriptorType =
				.STORAGE_BUFFER_DYNAMIC
			} else {
				assert(false, "Invalid buffer binding") 
			}
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
	is_buffer_binding :: #force_inline proc(p_binding_type: BindGroupLayoutBindingType) -> bool{
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

	@(private="file")
	safe_destroy_descriptor_set :: proc(p_user_data: rawptr) {
		descriptor_set := (^vk.DescriptorSet)(p_user_data)

		vk.FreeDescriptorSets(
			G_RENDERER.device,
			INTERNAL.descriptor_pool,
			1,
			descriptor_set,
		)
	}

	//---------------------------------------------------------------------------//
}
