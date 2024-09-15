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
		vk.FreeDescriptorSets(
			G_RENDERER.device,
			INTERNAL.descriptor_pool,
			1,
			&backend_bind_group.vk_descriptor_set,
		)
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

		image_write_idx := 0
		buffer_write_idx := 0

		bind_group_layout_idx := get_bind_group_layout_idx(bind_group.desc.layout_ref)
		bind_group_layout := &g_resources.bind_group_layouts[bind_group_layout_idx]

		num_descriptor_writes: u32 = 0
		for binding, binding_idx in bind_group_layout.desc.bindings {

			if is_buffer_binding(binding.type) {

				buffer_binding := p_bind_group_update.buffers[buffer_write_idx]

				if buffer_binding.buffer_ref == InvalidBufferRef {
					// Write null descriptor 
					buffer_write_idx += 1
					continue
				}

				binding_buffer_idx := get_buffer_idx(buffer_binding.buffer_ref)
				buffer := &g_resources.buffers[binding_buffer_idx]
				backend_buffer := &g_resources.backend_buffers[binding_buffer_idx]

				buffer_writes[buffer_write_idx].buffer = backend_buffer.vk_buffer
				buffer_writes[buffer_write_idx].offset = vk.DeviceSize(buffer_binding.offset)
				buffer_writes[buffer_write_idx].range = vk.DeviceSize(buffer_binding.size)

				descriptor_writes[num_descriptor_writes] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					dstBinding      = u32(binding_idx),
					dstSet          = backend_bind_group.vk_descriptor_set,
					pBufferInfo     = &buffer_writes[buffer_write_idx],
				}

				if .UniformBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType = .UNIFORM_BUFFER
				} else if .DynamicUniformBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType =
					.UNIFORM_BUFFER_DYNAMIC
				} else if .StorageBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType = .STORAGE_BUFFER
				} else if .DynamicStorageBuffer in buffer.desc.usage {
					descriptor_writes[num_descriptor_writes].descriptorType =
					.STORAGE_BUFFER_DYNAMIC
				} else {
					assert(false) // Unsupported descriptor type
				}

				num_descriptor_writes += 1
				buffer_write_idx += 1
				continue
			}

			if is_image_binding(binding.type) {

				image_binding := p_bind_group_update.images[image_write_idx]

				if image_binding.image_ref == InvalidImageRef {
					// Write null descriptor
					image_write_idx += 1
					continue
				}

				image := &g_resources.images[get_image_idx(image_binding.image_ref)]
				backend_image := &g_resources.backend_images[get_image_idx(image_binding.image_ref)]

				if image_binding.mip > 0 {
					image_writes[image_write_idx].imageView =
						backend_image.per_mip_vk_view[image_binding.mip]

				} else {
					image_writes[image_write_idx].imageView = backend_image.all_mips_vk_view
				}

				if binding.type == .StorageImage {
					image_writes[image_write_idx].imageLayout = .GENERAL	
				} else if image.desc.format > .DepthStencilFormatsStart && image.desc.format < .DepthStencilFormatsEnd {
					image_writes[image_write_idx].imageLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL
				} else if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {
					image_writes[image_write_idx].imageLayout = .DEPTH_READ_ONLY_OPTIMAL
				}else {
					image_writes[image_write_idx].imageLayout = .SHADER_READ_ONLY_OPTIMAL		
				}

				descriptor_writes[num_descriptor_writes] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					dstBinding      = u32(binding_idx),
					dstSet          = backend_bind_group.vk_descriptor_set,
					pImageInfo      = &image_writes[image_write_idx],
				}

				if binding.type == .Image {
					descriptor_writes[num_descriptor_writes].descriptorType = .SAMPLED_IMAGE
				} else {
					descriptor_writes[num_descriptor_writes].descriptorType = .STORAGE_IMAGE
				}

				image_write_idx += 1
				num_descriptor_writes += 1
				continue
			}
		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(num_descriptor_writes),
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

}
