package renderer

import "core:mem"
import "core:strings"

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:log"
	import vk "vendor:vulkan"
	import vma "../third_party/vma"
	import "../common"

	//---------------------------------------------------------------------------//

	@(private = "file")
	MAX_BINDLESS_COUNT :: 2048

	//---------------------------------------------------------------------------//

	@(private)
	BackendImageResource :: struct {
		vk_image:          vk.Image,
		vk_layout_per_mip: []vk.ImageLayout,
		all_mips_vk_view:  vk.ImageView,
		per_mip_vk_view:   []vk.ImageView,
		allocation:        vma.Allocation,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_TYPE_MAPPING := map[ImageType]vk.ImageType {
		.OneDimensional   = vk.ImageType.D1,
		.TwoDimensional   = vk.ImageType.D2,
		.ThreeDimensional = vk.ImageType.D3,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_IMAGE_VIEW_TYPE_MAPPING := map[ImageType]vk.ImageViewType {
		.OneDimensional   = vk.ImageViewType.D1,
		.TwoDimensional   = vk.ImageViewType.D2,
		.ThreeDimensional = vk.ImageViewType.D3,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	G_SAMPLE_COUNT_MAPPING := map[ImageSampleFlagBits]vk.SampleCountFlag {
		._1  = ._1,
		._2  = ._2,
		._4  = ._4,
		._8  = ._8,
		._16 = ._16,
		._32 = ._32,
		._64 = ._64,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	RunningImageUpload :: struct {
		image_ref:             ImageRef,
		upload_finished_fence: vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		staging_buffer:                 BufferRef,
		stating_buffer_offset:          u32,
		bindless_descriptor_pool:       vk.DescriptorPool,
		bindless_descriptor_set_layout: vk.DescriptorSetLayout,
		bindless_descriptor_set:        vk.DescriptorSet,
		immutable_samplers:             []vk.Sampler,
		running_image_uploads:          [dynamic]RunningImageUpload,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_images :: proc() {
		INTERNAL.staging_buffer = allocate_buffer_ref(
			common.create_name("ImageStagingBuffer"),
		)
		staging_buffer := get_buffer(INTERNAL.staging_buffer)
		staging_buffer.desc.size = common.MEGABYTE * 128
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}
		create_buffer(INTERNAL.staging_buffer)

		create_bindless_descriptor_array()

		INTERNAL.running_image_uploads = make(
			[dynamic]RunningImageUpload,
			G_RENDERER_ALLOCATORS.main_allocator,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_texture_image :: proc(
		p_image_ref: ImageRef,
		p_image: ^ImageResource,
	) -> bool {


		// @TODO Bindless
		// - get an index into the descriptor array
		// - add a descriptor update entry
		// - issue a descriptor update call at the end of the frame
		// - think about storage images 

		// Map vk image type
		vk_image_type, type_found := G_IMAGE_TYPE_MAPPING[p_image.desc.type]
		if type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(p_image.desc.name),
				p_image.desc.type,
			)
			return false
		}

		// Map vk image view type
		vk_image_view_type, view_type_found :=
			G_IMAGE_VIEW_TYPE_MAPPING[p_image.desc.type]
		if view_type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(p_image.desc.name),
				p_image.desc.type,
			)
			return false
		}

		// Map vk image format
		vk_image_format, format_found := G_IMAGE_FORMAT_MAPPING[p_image.desc.format]
		if format_found == false {
			log.warnf(
				"Failed to create image %s, unsupported format: %s\n",
				common.get_string(p_image.desc.name),
				p_image.desc.type,
			)
			return false
		}

		// Determine usage and aspect
		image_aspect := ImageAspectFlags{.Color}
		usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_DST}

		if .Storage in p_image.desc.flags {
			usage += {.STORAGE}
		}

		// Determine sample count
		vk_sample_count_flags := vk.SampleCountFlags{}
		for sample_count in ImageSampleFlagBits {
			if sample_count in p_image.desc.sample_count_flags {
				vk_sample_count_flags += {G_SAMPLE_COUNT_MAPPING[sample_count]}
			}
		}

		// Create image
		image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			mipLevels = u32(p_image.desc.mip_count),
			arrayLayers = 1,
			extent = {
				width = p_image.desc.dimensions.x,
				height = p_image.desc.dimensions.y,
				depth = p_image.desc.dimensions.z,
			},
			imageType = vk_image_type,
			format = vk_image_format,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = usage,
			sharingMode = .EXCLUSIVE,
			samples = vk_sample_count_flags,
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		if res := vma.create_image(
			   G_RENDERER.vma_allocator,
			   &image_create_info,
			   &alloc_create_info,
			   &p_image.vk_image,
			   &p_image.allocation,
			   nil,
		   );
		   res != .SUCCESS {
			log.warnf("Failed to create image %s", res)
			return false
		}


		vk_name := strings.clone_to_cstring(
			common.get_string(p_image.desc.name),
			G_RENDERER_ALLOCATORS.names_allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(p_image.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)


		// Create image view containing all of the mips
		{
			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = p_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {
					aspectMask = vk_map_image_aspect(image_aspect),
					levelCount = u32(p_image.desc.mip_count),
					layerCount = 1,
				},
			}

			if
			   vk.CreateImageView(
				   G_RENDERER.device,
				   &view_create_info,
				   nil,
				   &p_image.all_mips_vk_view,
			   ) !=
			   .SUCCESS {
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					p_image.vk_image,
					p_image.allocation,
				)
				return false
			}


			vk_name := strings.clone_to_cstring(
				common.get_string(p_image.desc.name),
				G_RENDERER_ALLOCATORS.names_allocator,
			)

			name_info := vk.DebugUtilsObjectNameInfoEXT {
				sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
				objectHandle = u64(p_image.all_mips_vk_view),
				objectType   = .IMAGE_VIEW,
				pObjectName  = vk_name,
			}

			vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		}

		// Now create image views per mip
		{
			p_image.per_mip_vk_view = make(
				[]vk.ImageView,
				u32(p_image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			p_image.vk_layout_per_mip = make(
				[]vk.ImageLayout,
				u32(p_image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			num_image_views_created := 0

			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = p_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {
					aspectMask = {.COLOR},
					levelCount = 1,
					layerCount = 1,
				},
			}

			for i in 0 ..< p_image.desc.mip_count {
				p_image.vk_layout_per_mip[i] = .UNDEFINED
				view_create_info.subresourceRange.baseMipLevel = u32(i)
				if
				   vk.CreateImageView(
					   G_RENDERER.device,
					   &view_create_info,
					   nil,
					   &p_image.per_mip_vk_view[i],
				   ) !=
				   .SUCCESS {
					break
				}

				vk_name := strings.clone_to_cstring(
					common.get_string(p_image.desc.name),
					G_RENDERER_ALLOCATORS.names_allocator,
				)

				name_info := vk.DebugUtilsObjectNameInfoEXT {
					sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
					objectHandle = u64(p_image.per_mip_vk_view[i]),
					objectType   = .IMAGE_VIEW,
					pObjectName  = vk_name,
				}

				vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)


				num_image_views_created += 1
			}

			// Free the created image views if we failed to create any of the mip views
			if num_image_views_created < int(p_image.desc.mip_count) {
				vk.DestroyImageView(G_RENDERER.device, p_image.all_mips_vk_view, nil)
				for i in 0 ..= num_image_views_created {
					vk.DestroyImageView(
						G_RENDERER.device,
						p_image.per_mip_vk_view[i],
						nil,
					)
				}
				// Delete the image itself
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					p_image.vk_image,
					p_image.allocation,
				)
				return false
			}
		}

		texture_copy := TextureCopy {
			buffer             = INTERNAL.staging_buffer,
			image              = p_image_ref,
			mip_buffer_offsets = make(
				[]u32,
				int(p_image.desc.mip_count),
				G_RENDERER_ALLOCATORS.frame_allocator,
			),
		}

		texture_copy.image = p_image_ref
		texture_copy.buffer = INTERNAL.staging_buffer

		staging_buffer := get_buffer(INTERNAL.staging_buffer)

		// Queue image copies
		for mip_data, i in p_image.desc.data_per_mip {

			// Make sure we have enough space in the staging buffer
			assert(
				INTERNAL.stating_buffer_offset + u32(len(mip_data)) <
				staging_buffer.desc.size,
			)

			mem.copy(
				mem.ptr_offset(
					staging_buffer.mapped_ptr,
					INTERNAL.stating_buffer_offset,
				),
				raw_data(mip_data),
				len(mip_data),
			)

			texture_copy.mip_buffer_offsets[i] = INTERNAL.stating_buffer_offset

			INTERNAL.stating_buffer_offset += u32(len(mip_data))
		}

		append(&G_RENDERER.queued_textures_copies, texture_copy)

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_swap_images :: proc() {
		G_RENDERER.swap_image_refs = make(
			[]ImageRef,
			u32(len(G_RENDERER.swapchain_images)),
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for vk_swap_image, i in G_RENDERER.swapchain_images {
			ref := allocate_image_ref(common.create_name("SwapImage"))

			swap_image := get_image(ref)

			swap_image.desc.type = .TwoDimensional
			swap_image.desc.format =
				G_IMAGE_FORMAT_MAPPING_VK[G_RENDERER.swapchain_format.format]
			swap_image.desc.mip_count = 1
			swap_image.desc.dimensions = {
				G_RENDERER.swap_extent.width,
				G_RENDERER.swap_extent.height,
				1,
			}
			swap_image.desc.flags = {.SwapImage}

			swap_image.vk_image = vk_swap_image
			swap_image.all_mips_vk_view = G_RENDERER.swapchain_image_views[i]

			G_RENDERER.swap_image_refs[i] = ref
		}
	}


	@(private)
	backend_create_depth_buffer :: proc(
		p_name: common.Name,
		p_depth_buffer_desc: ImageDesc,
		p_image_ref: ImageRef,
		p_depth_image: ^ImageResource,
	) -> bool {

		assert(
			p_depth_buffer_desc.format > .DepthFormatsStart &&
			p_depth_buffer_desc.format < .DepthFormatsEnd,
		)

		depth_image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {
				p_depth_buffer_desc.dimensions.x,
				p_depth_buffer_desc.dimensions.y,
				p_depth_buffer_desc.dimensions.z,
			},
			mipLevels = 1,
			arrayLayers = 1,
			format = G_IMAGE_FORMAT_MAPPING[p_depth_buffer_desc.format],
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			sharingMode = .EXCLUSIVE,
			samples = {._1},
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		if
		   vma.create_image(
			   G_RENDERER.vma_allocator,
			   &depth_image_create_info,
			   &alloc_create_info,
			   &p_depth_image.vk_image,
			   &p_depth_image.allocation,
			   nil,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create depth buffer")
			return false
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(p_name),
			G_RENDERER_ALLOCATORS.names_allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(p_depth_image.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)


		view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = p_depth_image.vk_image,
			viewType = .D2,
			format = G_IMAGE_FORMAT_MAPPING[p_depth_buffer_desc.format],
			subresourceRange = {aspectMask = {.DEPTH}, levelCount = 1, layerCount = 1},
		}

		if
		   vk.CreateImageView(
			   G_RENDERER.device,
			   &view_create_info,
			   nil,
			   &p_depth_image.all_mips_vk_view,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create image view")
			return false
		}

		name_info = vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(p_depth_image.all_mips_vk_view),
			objectType   = .IMAGE_VIEW,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		return true
	}

	//---------------------------------------------------------------------------//

	backend_destroy_image :: proc(p_image: ^ImageResource) {
		vk.DestroyImageView(G_RENDERER.device, p_image.all_mips_vk_view, nil)
		for image_view in p_image.per_mip_vk_view {
			vk.DestroyImageView(G_RENDERER.device, image_view, nil)
		}
		vma.destroy_image(G_RENDERER.vma_allocator, p_image.vk_image, nil)
		delete(p_image.per_mip_vk_view, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(p_image.vk_layout_per_mip, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_execute_queued_texture_copies :: proc(p_cmd_buff_ref: CommandBufferRef) {

		cmd_buff := get_command_buffer(p_cmd_buff_ref)

		VkCopyEntry :: struct {
			buffer:     vk.Buffer,
			image:      vk.Image,
			mip_copies: []vk.BufferImageCopy,
		}

		to_transfer_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(to_transfer_barriers, G_RENDERER_ALLOCATORS.temp_allocator)

		vk_copies := make(
			[]VkCopyEntry,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(vk_copies, G_RENDERER_ALLOCATORS.temp_allocator)

		to_sample_barriers := make(
			[]vk.ImageMemoryBarrier,
			len(G_RENDERER.queued_textures_copies),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(to_sample_barriers, G_RENDERER_ALLOCATORS.temp_allocator)

		for _, i in G_RENDERER.queued_textures_copies {

			texture_copy := G_RENDERER.queued_textures_copies[i]
			image := get_image(texture_copy.image)
			buffer := get_buffer(texture_copy.buffer)

			// Crate a transfer barrier for the entire texture, including all of it's mips
			{
				image_barrier := &to_transfer_barriers[i]
				image_barrier.sType = .IMAGE_MEMORY_BARRIER
				image_barrier.oldLayout = .UNDEFINED // #FIXME ASSUMPTION UNTIL WE HAVE IMAGE LAYOUT TRACKING
				image_barrier.newLayout = .TRANSFER_DST_OPTIMAL
				image_barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
				image_barrier.image = image.vk_image
				image_barrier.subresourceRange.aspectMask = {.COLOR}
				image_barrier.subresourceRange.baseArrayLayer = 0
				image_barrier.subresourceRange.layerCount = 1
				image_barrier.subresourceRange.baseMipLevel = 0
				image_barrier.subresourceRange.levelCount = u32(image.desc.mip_count)
				image_barrier.dstAccessMask = {.TRANSFER_WRITE}
			}

			// Create a to-sample barrier for the entire texture, including all of it's mips
			{
				image_barrier := &to_sample_barriers[i]
				image_barrier^ = to_transfer_barriers[i]

				image_barrier.sType = .IMAGE_MEMORY_BARRIER
				image_barrier.oldLayout = .TRANSFER_DST_OPTIMAL
				image_barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
				image_barrier.dstAccessMask = {.SHADER_READ}
			}

			vk_copy_entry := VkCopyEntry {
				buffer     = buffer.vk_buffer,
				image      = image.vk_image,
				mip_copies = make(
					[]vk.BufferImageCopy,
					u32(len(texture_copy.mip_buffer_offsets)),
					G_RENDERER_ALLOCATORS.temp_allocator,
				),
			}

			// Create the vulkan copies
			for offset, mip in texture_copy.mip_buffer_offsets {

				vk_copy_entry.mip_copies[mip] = {
					bufferOffset = vk.DeviceSize(offset),
					imageSubresource = {
						aspectMask = {.COLOR},
						baseArrayLayer = 0,
						layerCount = 1,
						mipLevel = u32(mip),
					},
					imageExtent = {
						width = image.desc.dimensions[0] << u32(mip),
						height = image.desc.dimensions[1] << u32(mip),
						depth = 1,
					},
				}


				image.vk_layout_per_mip[mip] = .SHADER_READ_ONLY_OPTIMAL
			}

			vk_copies[i] = vk_copy_entry
		}
		defer {
			for vk_copy in vk_copies {
				defer delete(vk_copy.mip_copies, G_RENDERER_ALLOCATORS.temp_allocator)

			}
		}

		// Transition the images to transfer
		vk.CmdPipelineBarrier(
			cmd_buff.vk_cmd_buff,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			0,
			nil,
			u32(len(vk_copies)),
			&to_transfer_barriers[0],
		)

		// Copy the data image
		for copy, i in vk_copies {

			vk.CmdCopyBufferToImage(
				cmd_buff.vk_cmd_buff,
				copy.buffer,
				copy.image,
				.TRANSFER_DST_OPTIMAL,
				u32(len(copy.mip_copies)),
				raw_data(copy.mip_copies),
			)

			// Transition the image to sample
			vk.CmdPipelineBarrier(
				cmd_buff.vk_cmd_buff,
				{.TRANSFER},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&to_sample_barriers[i],
			)

			// Create a fence so that we can update the descriptor in the bindless array
			upload_finished_fence_create_info := vk.FenceCreateInfo {
				sType = .FENCE_CREATE_INFO,
			}

			running_image_upload := RunningImageUpload {
				image_ref = G_RENDERER.queued_textures_copies[i].image,
			}

			vk.CreateFence(
				G_RENDERER.device,
				&upload_finished_fence_create_info,
				nil,
				&running_image_upload.upload_finished_fence,
			)
		}

	}
	//---------------------------------------------------------------------------//

	@(private = "file")
	create_bindless_descriptor_array :: proc() {

		// Create samplers
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
		// Create a descriptor poll for the bindless array and immutable samplers
		{
			pool_sizes := []vk.DescriptorPoolSize{
				{type = .SAMPLER, descriptorCount = len(SamplerType)},
				{type = .SAMPLED_IMAGE, descriptorCount = MAX_BINDLESS_COUNT},
			}

			descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
				sType         = .DESCRIPTOR_POOL_CREATE_INFO,
				maxSets       = 1,
				poolSizeCount = 1,
				pPoolSizes    = raw_data(pool_sizes),
			}

			vk.CreateDescriptorPool(
				G_RENDERER.device,
				&descriptor_pool_create_info,
				nil,
				&INTERNAL.bindless_descriptor_pool,
			)

		}

		// Create the bindings layout and the layout itself
		{
			binding_flags := vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND}

			flags_create_info := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
				sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
				bindingCount  = 1,
				pBindingFlags = &binding_flags,
			}

			set_bindings := []vk.DescriptorSetLayoutBinding{
				{
					binding = 0,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 1,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 2,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 3,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 4,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 5,
					descriptorCount = 1,
					descriptorType = .SAMPLER,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
				{
					binding = 6,
					descriptorCount = MAX_BINDLESS_COUNT,
					descriptorType = .SAMPLED_IMAGE,
					pImmutableSamplers = raw_data(INTERNAL.immutable_samplers),
					stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE},
				},
			}

			descriptor_set_layout_create_info := vk.DescriptorSetLayoutCreateInfo {
				sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
				bindingCount = u32(len(set_bindings)),
				pBindings    = raw_data(set_bindings),
			}

			res := vk.CreateDescriptorSetLayout(
				G_RENDERER.device,
				&descriptor_set_layout_create_info,
				nil,
				&INTERNAL.bindless_descriptor_set_layout,
			)
			assert(res == .SUCCESS)

			// Finally, allocate the descriptor set 
			allocate_info := vk.DescriptorSetAllocateInfo {
				sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
				pSetLayouts        = &INTERNAL.bindless_descriptor_set_layout,
				descriptorPool     = INTERNAL.bindless_descriptor_pool,
				descriptorSetCount = 1,
			}

			res = vk.AllocateDescriptorSets(
				G_RENDERER.device,
				&allocate_info,
				&INTERNAL.bindless_descriptor_set,
			)
			assert(res == .SUCCESS)
		}
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_bind_bindless_array_and_immutable_samplers :: proc(
		p_cmd_buffer: ^CommandBufferResource,
		p_pipeline_layout: ^PipelineLayoutResource,
		p_target: u32,
		p_bind_point: PipelineType,
	) {

		vk.CmdBindDescriptorSets(
			p_cmd_buffer.vk_cmd_buff,
			map_pipeline_bind_point(p_bind_point),
			p_pipeline_layout.vk_pipeline_layout,
			p_target,
			1,
			&INTERNAL.bindless_descriptor_set,
			0,
			nil,
		)

	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_update_images :: proc(p_dt: f32) {

		running_image_uploads := make(
			[dynamic]RunningImageUpload,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		bindless_writes := make(
			[]vk.WriteDescriptorSet,
			len(INTERNAL.running_image_uploads),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)

		defer delete(bindless_writes, G_RENDERER_ALLOCATORS.temp_allocator)

		next_descriptor_write_idx := 0
		for image_upload, i in INTERNAL.running_image_uploads {

			// Check if the upload is finished
			if
			   vk.GetFenceStatus(
				   G_RENDERER.device,
				   image_upload.upload_finished_fence,
			   ) ==
			   .SUCCESS {

				// If it is, then update the descriptor in the bindless array
				image := get_image(image_upload.image_ref)

				img_info := vk.DescriptorImageInfo {
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
					imageView   = image.all_mips_vk_view,
				}
				bindless_writes[next_descriptor_write_idx] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					descriptorType  = .SAMPLED_IMAGE,
					dstSet          = INTERNAL.bindless_descriptor_set,
					pImageInfo      = &img_info,
					dstArrayElement = image.bindless_idx,
					dstBinding      = 1,
				}

				next_descriptor_write_idx += 1
			} else {
				// Otherwise just keep add it to the new array containing only the 
				// uploads that are still running

				append(&running_image_uploads, image_upload)
			}
		}

		// Swap the arrays to only keep the running uploads
		delete(INTERNAL.running_image_uploads)
		INTERNAL.running_image_uploads = running_image_uploads 

		// Update the bindless array
		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(next_descriptor_write_idx),
			raw_data(bindless_writes),
			0,
			nil,
		)
	}

	//---------------------------------------------------------------------------//

}
