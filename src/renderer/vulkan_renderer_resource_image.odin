#+feature dynamic-literals

package renderer

//---------------------------------------------------------------------------//

import "../common"

import vma "../third_party/vma"
import vk "vendor:vulkan"

import "base:intrinsics"
import "core:log"
import "core:math/linalg/glsl"
import "core:strings"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	BackendImageResource :: struct {
		vk_image:          vk.Image,
		vk_image_view:     vk.ImageView, // This view contains all of the array and all of the mips per array
		vk_all_mips_views: []vk.ImageView, // These array contain an image view for each array level, with all mips per level
		vk_views:          [][]vk.ImageView, // Per array, per mip image view
		vk_layouts:        [][]vk.ImageLayout,
		allocation:        vma.Allocation,
		aspect_mask:       ImageAspectFlags,
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
	G_IMAGE_VIEW_TYPE_MAPPING_ARRAY := map[ImageType]vk.ImageViewType {
		.OneDimensional = vk.ImageViewType.D1_ARRAY,
		.TwoDimensional = vk.ImageViewType.D2_ARRAY,
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
	FinishedImageUpload :: struct {
		image_ref: ImageRef,
		fence_idx: u8,
		mip:       u32,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	BindlessArrayUpdate :: struct {
		image_ref:         ImageRef,
		use_default_image: bool,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		// Buffer used to upload the initial contents of the images
		bindless_descriptor_pool: vk.DescriptorPool,
		bindless_array_updates:   [dynamic]BindlessArrayUpdate,
		finished_image_uploads:   [dynamic]FinishedImageUpload,
		default_image_ref:        ImageRef,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_init :: proc() {
		INTERNAL.bindless_array_updates = make([dynamic]BindlessArrayUpdate)
		INTERNAL.finished_image_uploads = make([dynamic]FinishedImageUpload, get_frame_allocator())
		INTERNAL.default_image_ref = InvalidImageRef
	}

	@(private)
	backend_image_create_texture :: proc(p_image_ref: ImageRef) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena, common.MEGABYTE)
		defer common.arena_delete(temp_arena)

		image_idx := image_get_idx(p_image_ref)

		image := &g_resources.images[image_idx]
		backend_image := &g_resources.backend_images[image_idx]

		// Map vk image type
		vk_image_type, type_found := G_IMAGE_TYPE_MAPPING[image.desc.type]
		if type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Map vk image view type
		vk_image_view_type, view_type_found := G_IMAGE_VIEW_TYPE_MAPPING[image.desc.type]
		if image.desc.array_size > 1 {
			vk_image_view_type, view_type_found = G_IMAGE_VIEW_TYPE_MAPPING_ARRAY[image.desc.type]
		}

		if view_type_found == false {
			log.warnf(
				"Failed to create image %s, unsupported type: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Map vk image format
		vk_image_format, format_found := G_IMAGE_FORMAT_MAPPING[image.desc.format]
		if format_found == false {
			log.warnf(
				"Failed to create image %s, unsupported format: %s\n",
				common.get_string(image.desc.name),
				image.desc.type,
			)
			return false
		}

		// Determine usage and aspect
		image_aspect := ImageAspectFlags{.Color}
		usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_DST}

		if .Storage in image.desc.flags {
			usage += {.STORAGE}
		}

		// Determine sample count
		vk_sample_count_flags := vk.SampleCountFlags{}
		for sample_count in ImageSampleFlagBits {
			if sample_count in image.desc.sample_count_flags {
				vk_sample_count_flags += {G_SAMPLE_COUNT_MAPPING[sample_count]}
			}
		}

		// Create image
		image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			mipLevels = u32(image.desc.mip_count),
			arrayLayers = 1,
			extent = {
				width = image.desc.dimensions.x,
				height = image.desc.dimensions.y,
				depth = image.desc.dimensions.z,
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
			&backend_image.vk_image,
			&backend_image.allocation,
			nil,
		); res != .SUCCESS {
			log.warnf("Failed to create image %s", res)
			return false
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(image.desc.name),
			temp_arena.allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(backend_image.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		backend_image.vk_all_mips_views = make(
			[]vk.ImageView,
			1,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		// Create image view containing all of the mips
		{
			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = backend_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {
					aspectMask = vk_map_image_aspect(image_aspect),
					levelCount = u32(image.desc.mip_count),
					layerCount = 1,
				},
			}

			if vk.CreateImageView(
				   G_RENDERER.device,
				   &view_create_info,
				   nil,
				   &backend_image.vk_all_mips_views[0],
			   ) !=
			   .SUCCESS {
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					backend_image.vk_image,
					backend_image.allocation,
				)
				return false
			}

			backend_image.vk_image_view = backend_image.vk_all_mips_views[0]

			image_view_name_info := vk.DebugUtilsObjectNameInfoEXT {
				sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
				objectHandle = u64(backend_image.vk_all_mips_views[0]),
				objectType   = .IMAGE_VIEW,
				pObjectName  = vk_name,
			}

			vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &image_view_name_info)

		}

		// Now create image views per mip
		{
			backend_image.vk_views = make(
				[][]vk.ImageView,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_image.vk_views[0] = make(
				[]vk.ImageView,
				u32(image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_image.vk_layouts = make(
				[][]vk.ImageLayout,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_image.vk_layouts[0] = make(
				[]vk.ImageLayout,
				u32(image.desc.mip_count),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			num_image_views_created := 0

			view_create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = backend_image.vk_image,
				viewType = vk_image_view_type,
				format = vk_image_format,
				subresourceRange = {aspectMask = {.COLOR}, layerCount = 1},
			}

			for i in 0 ..< image.desc.mip_count {

				backend_image.vk_layouts[0][i] = .UNDEFINED

				view_create_info.subresourceRange.baseMipLevel = u32(i)
				view_create_info.subresourceRange.levelCount = u32(image.desc.mip_count) - u32(i)

				if vk.CreateImageView(
					   G_RENDERER.device,
					   &view_create_info,
					   nil,
					   &backend_image.vk_views[0][i],
				   ) !=
				   .SUCCESS {
					break
				}

				image_view_name_info := vk.DebugUtilsObjectNameInfoEXT {
					sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
					objectHandle = u64(backend_image.vk_views[0][i]),
					objectType   = .IMAGE_VIEW,
					pObjectName  = vk_name,
				}

				vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &image_view_name_info)

				num_image_views_created += 1
			}

			// Free the created image views if we failed to create any of the mip views
			if num_image_views_created < int(image.desc.mip_count) {
				vk.DestroyImageView(G_RENDERER.device, backend_image.vk_all_mips_views[0], nil)
				for i in 0 ..< num_image_views_created {
					vk.DestroyImageView(G_RENDERER.device, backend_image.vk_views[0][i], nil)
				}
				// Delete the image itself
				vma.destroy_image(
					G_RENDERER.vma_allocator,
					backend_image.vk_image,
					backend_image.allocation,
				)
				delete(backend_image.vk_all_mips_views, G_RENDERER_ALLOCATORS.resource_allocator)
				delete(backend_image.vk_views[0], G_RENDERER_ALLOCATORS.resource_allocator)
				delete(backend_image.vk_views, G_RENDERER_ALLOCATORS.resource_allocator)
				delete(backend_image.vk_layouts[0], G_RENDERER_ALLOCATORS.resource_allocator)
				delete(backend_image.vk_layouts, G_RENDERER_ALLOCATORS.resource_allocator)
				return false
			}
		}

		append(
			&INTERNAL.bindless_array_updates,
			BindlessArrayUpdate{image_ref = p_image_ref, use_default_image = true},
		)

		backend_image.aspect_mask = image_aspect

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_create_swap_images :: proc() {

		// If those images are already created, this means that the swapchain is getting recreated
		is_recreating_swapchain := len(G_RENDERER.swap_image_refs) > 0

		if is_recreating_swapchain == false {
			G_RENDERER.swap_image_refs = make(
				[]ImageRef,
				u32(len(G_RENDERER.swapchain_images)),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			for _, i in G_RENDERER.swap_image_refs {
				G_RENDERER.swap_image_refs[i] = image_allocate(common.create_name("SwapImage"))
			}
		}

		for vk_swap_image, i in G_RENDERER.swapchain_images {
			ref := G_RENDERER.swap_image_refs[i]
			image_idx := image_get_idx(ref)

			swap_image := &g_resources.images[image_idx]
			backend_swap_image := &g_resources.backend_images[image_idx]

			swap_image.desc.type = .TwoDimensional
			swap_image.desc.format = G_IMAGE_FORMAT_MAPPING_VK[G_RENDERER.swapchain_format.format]
			swap_image.desc.mip_count = 1
			swap_image.desc.dimensions = {
				G_RENDERER.swap_extent.width,
				G_RENDERER.swap_extent.height,
				1,
			}
			swap_image.desc.flags = {.SwapImage}

			backend_swap_image.vk_image_view = G_RENDERER.swapchain_image_views[i]

			backend_swap_image.vk_image = vk_swap_image
			backend_swap_image.vk_all_mips_views = make(
				[]vk.ImageView,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			backend_swap_image.vk_all_mips_views[0] = G_RENDERER.swapchain_image_views[i]

			backend_swap_image.vk_views = make(
				[][]vk.ImageView,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.vk_views[0] = make(
				[]vk.ImageView,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.vk_views[0][0] = G_RENDERER.swapchain_image_views[i]
			backend_swap_image.vk_layouts = make(
				[][]vk.ImageLayout,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.vk_layouts[0] = make(
				[]vk.ImageLayout,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			backend_swap_image.vk_layouts[0][0] = .UNDEFINED

			G_RENDERER.swap_image_refs[i] = ref
		}
	}


	@(private)
	backend_image_create :: proc(p_image_ref: ImageRef) -> (res: bool) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_idx := image_get_idx(p_image_ref)
		image := &g_resources.images[image_idx]
		image_backend := &g_resources.backend_images[image_idx]

		image_type := vk.ImageType.D1
		#partial switch image.desc.type {
		case .TwoDimensional:
			image_type = .D2
		case .ThreeDimensional:
			image_type = .D3
		}

		usage := vk.ImageUsageFlags{.TRANSFER_SRC, .TRANSFER_DST}
		aspect_mask := ImageAspectFlags{}

		if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {
			usage += {.DEPTH_STENCIL_ATTACHMENT}
			aspect_mask += {.Depth}

			if image.desc.format > .DepthStencilFormatsStart &&
			   image.desc.format < .DepthStencilFormatsEnd {
				aspect_mask += {.Stencil}
			}

		} else {
			aspect_mask += {.Color}
			if image.desc.format < .CompressedFormatsStart ||
			   image.desc.format > .CompressedFormatsEnd {
				usage += {.COLOR_ATTACHMENT}
			}
		}

		if .Sampled in image.desc.flags {
			usage += {.SAMPLED}
		}
		if .Storage in image.desc.flags {
			usage += {.STORAGE}
		}

		image_create_info := vk.ImageCreateInfo {
			sType         = .IMAGE_CREATE_INFO,
			imageType     = image_type,
			extent        = {
				image.desc.dimensions.x,
				image.desc.dimensions.y,
				image.desc.dimensions.z,
			},
			mipLevels     = image.desc.mip_count,
			arrayLayers   = image.desc.array_size,
			format        = G_IMAGE_FORMAT_MAPPING[image.desc.format],
			tiling        = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage         = usage,
			sharingMode   = .EXCLUSIVE,
			samples       = {._1},
		}

		alloc_create_info := vma.AllocationCreateInfo {
			usage = .AUTO,
		}

		create_result := vma.create_image(
			G_RENDERER.vma_allocator,
			&image_create_info,
			&alloc_create_info,
			&image_backend.vk_image,
			&image_backend.allocation,
			nil,
		)
		if create_result != .SUCCESS {
			return false
		}
		defer if res == false {
			vma.destroy_image(
				G_RENDERER.vma_allocator,
				image_backend.vk_image,
				image_backend.allocation,
			)
		}

		vk_name := strings.clone_to_cstring(
			common.get_string(image.desc.name),
			temp_arena.allocator,
		)

		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(image_backend.vk_image),
			objectType   = .IMAGE,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		view_type := vk.ImageViewType{}
		#partial switch image_type {
		case .D1:
			view_type = .D1 if image.desc.array_size == 1 else .D1_ARRAY
		case .D2:
			view_type = .D2 if image.desc.array_size == 1 else .D2_ARRAY
		case .D3:
			view_type = .D3
			assert(image.desc.array_size == 1)
		}

		view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image_backend.vk_image,
			viewType = view_type,
			format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
			subresourceRange = {
				aspectMask = vk_map_image_aspect(aspect_mask),
				levelCount = image.desc.mip_count,
				layerCount = image.desc.array_size,
			},
		}

		// Create the image view with all array levels and all mips per array level
		if vk.CreateImageView(
			   G_RENDERER.device,
			   &view_create_info,
			   nil,
			   &image_backend.vk_image_view,
		   ) !=
		   .SUCCESS {
			log.warn("Failed to create image view")
			return false
		}
		defer if res == false {
			vk.DestroyImageView(G_RENDERER.device, image_backend.vk_image_view, nil)
		}

		name_info = vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectHandle = u64(image_backend.vk_image_view),
			objectType   = .IMAGE_VIEW,
			pObjectName  = vk_name,
		}

		vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

		if .AddToBindlessArray in image.desc.flags {
			append(
				&INTERNAL.bindless_array_updates,
				BindlessArrayUpdate{image_ref = p_image_ref, use_default_image = false},
			)
		}

		image_backend.vk_views = make(
			[][]vk.ImageView,
			image.desc.array_size,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		image_backend.vk_all_mips_views = make(
			[]vk.ImageView,
			image.desc.array_size,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		image_backend.vk_views = make(
			[][]vk.ImageView,
			image.desc.array_size,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		image_backend.vk_layouts = make(
			[][]vk.ImageLayout,
			image.desc.array_size,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		for i in 0 ..< image.desc.array_size {
			image_backend.vk_views[i] = make(
				[]vk.ImageView,
				image.desc.mip_count,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			image_backend.vk_layouts[i] = make(
				[]vk.ImageLayout,
				image.desc.mip_count,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		defer if res == false {

			for i in 0 ..< image.desc.array_size {
				delete(image_backend.vk_views[i], G_RENDERER_ALLOCATORS.resource_allocator)
				delete(image_backend.vk_layouts[i], G_RENDERER_ALLOCATORS.resource_allocator)
			}

			delete(image_backend.vk_all_mips_views, G_RENDERER_ALLOCATORS.resource_allocator)
			delete(image_backend.vk_views, G_RENDERER_ALLOCATORS.resource_allocator)
			delete(image_backend.vk_views, G_RENDERER_ALLOCATORS.resource_allocator)
		}

		// Create an image view for each array level
		for array_level in 0 ..< image.desc.array_size {

			view_create_info = vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = image_backend.vk_image,
				viewType = G_IMAGE_VIEW_TYPE_MAPPING[image.desc.type],
				format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
				subresourceRange = {
					aspectMask = vk_map_image_aspect(aspect_mask),
					levelCount = image.desc.mip_count,
					layerCount = 1,
					baseArrayLayer = array_level,
				},
			}

			if vk.CreateImageView(
				   G_RENDERER.device,
				   &view_create_info,
				   nil,
				   &image_backend.vk_all_mips_views[array_level],
			   ) !=
			   .SUCCESS {
				return false
			}

			name_info = vk.DebugUtilsObjectNameInfoEXT {
				sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
				objectHandle = u64(image_backend.vk_all_mips_views[array_level]),
				objectType   = .IMAGE_VIEW,
				pObjectName  = vk_name,
			}

			vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

			// Now, create a view for each mip in the array
			for mip in 0 ..< image.desc.mip_count {

				view_create_info = vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					image = image_backend.vk_image,
					viewType = G_IMAGE_VIEW_TYPE_MAPPING[image.desc.type],
					format = G_IMAGE_FORMAT_MAPPING[image.desc.format],
					subresourceRange = {
						aspectMask = vk_map_image_aspect(aspect_mask),
						levelCount = 1,
						layerCount = 1,
						baseArrayLayer = array_level,
						baseMipLevel = mip,
					},
				}

				if vk.CreateImageView(
					   G_RENDERER.device,
					   &view_create_info,
					   nil,
					   &image_backend.vk_views[array_level][mip],
				   ) !=
				   .SUCCESS {
					return false
				}


				name_info = vk.DebugUtilsObjectNameInfoEXT {
					sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
					objectHandle = u64(image_backend.vk_views[array_level][mip]),
					objectType   = .IMAGE_VIEW,
					pObjectName  = vk_name,
				}

				image_backend.vk_layouts[array_level][mip] = .UNDEFINED

				vk.SetDebugUtilsObjectNameEXT(G_RENDERER.device, &name_info)

			}
		}

		image_backend.aspect_mask = aspect_mask

		return true
	}

	//---------------------------------------------------------------------------//

	backend_image_destroy :: proc(p_image_ref: ImageRef) {
		img_idx := image_get_idx(p_image_ref)
		image := &g_resources.images[img_idx]
		backend_image := &g_resources.backend_images[img_idx]
		if (.SwapImage in image.desc.flags) == false {
			// For swap chain, these are destroyed in recreate_swapchain
			vma.destroy_image(G_RENDERER.vma_allocator, backend_image.vk_image, nil)
			vk.DestroyImageView(G_RENDERER.device, backend_image.vk_image_view, nil)

			for i in 0 ..< image.desc.array_size {
				for j in 0 ..< image.desc.mip_count {
					vk.DestroyImageView(G_RENDERER.device, backend_image.vk_views[i][j], nil)
				}
				vk.DestroyImageView(G_RENDERER.device, backend_image.vk_all_mips_views[i], nil)
			}
		}

		for i in 0 ..< image.desc.array_size {
			delete(backend_image.vk_views[i], G_RENDERER_ALLOCATORS.resource_allocator)
			delete(backend_image.vk_layouts[i], G_RENDERER_ALLOCATORS.resource_allocator)
		}

		delete(backend_image.vk_all_mips_views, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(backend_image.vk_views, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(backend_image.vk_views, G_RENDERER_ALLOCATORS.resource_allocator)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_update_bindless_array :: proc() {
		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		num_writes := len(INTERNAL.bindless_array_updates)
		if num_writes == 0 {
			return
		}

		bindless_bind_group_idx := bind_group_get_idx(G_RENDERER.bindless_bind_group_ref)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make([]vk.WriteDescriptorSet, u32(num_writes), temp_arena.allocator)

		image_infos := make([]vk.DescriptorImageInfo, u32(num_writes), temp_arena.allocator)

		if INTERNAL.default_image_ref == InvalidImageRef {
			INTERNAL.default_image_ref = image_find("DefaultImage")
		}

		backend_default_image := &g_resources.backend_images[image_get_idx(INTERNAL.default_image_ref)]

		for bindless_update, i in INTERNAL.bindless_array_updates {

			image_idx := image_get_idx(bindless_update.image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			// Update the descriptor in the bindless array
			image_infos[i] = vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView   = backend_image.vk_image_view,
			}

			if bindless_update.use_default_image {
				image_infos[i].imageView = backend_default_image.vk_image_view
			}

			descriptor_writes[i] = vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				descriptorCount = 1,
				descriptorType  = .SAMPLED_IMAGE,
				dstSet          = bindless_bind_group.vk_descriptor_set,
				pImageInfo      = &image_infos[i],
				dstArrayElement = image.bindless_idx,
				dstBinding      = u32(BindlessResourceSlot.TextureArray2D),
			}
		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(num_writes),
			raw_data(descriptor_writes),
			0,
			nil,
		)

		//INTERNAL.bindless_array_updates = make([dynamic]ImageRef, get_next_frame_allocator())
		clear(&INTERNAL.bindless_array_updates)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_upload_initialize :: proc(p_ref: ImageRef) {

		image_idx := image_get_idx(p_ref)
		image := &g_resources.images[image_idx]
		backend_image := &g_resources.backend_images[image_idx]

		for i in 0 ..< image.desc.mip_count {
			backend_image.vk_layouts[0][i] = .TRANSFER_DST_OPTIMAL
		}

		// If we have a dedicated transfer queue, then hand off ownership
		// to the transfer queue for the data uploads
		to_transfer_barrier := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			oldLayout = .UNDEFINED,
			newLayout = .TRANSFER_DST_OPTIMAL,
			image = backend_image.vk_image,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseArrayLayer = 0,
				layerCount = 1,
				baseMipLevel = 0,
				levelCount = u32(image.desc.mip_count),
			},
			dstAccessMask = {.TRANSFER_WRITE},
		}

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buffer_ref)]

		// if is_async_transfer_enabled() {
		// 	transfer_cmd_buff := frame_transfer_cmd_buffer_post_graphics_get()

		// 	// Acquire
		// 	vk.CmdPipelineBarrier(
		// 		transfer_cmd_buff,
		// 		{.BOTTOM_OF_PIPE},
		// 		{.TRANSFER},
		// 		nil,
		// 		0,
		// 		nil,
		// 		0,
		// 		nil,
		// 		1,
		// 		&to_transfer_barrier,
		// 	)

		// 	return
		// }

		// Otherwise just prepare it to copy
		vk.CmdPipelineBarrier(
			cmd_buffer.vk_cmd_buff,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			nil,
			0,
			nil,
			0,
			nil,
			1,
			&to_transfer_barrier,
		)

	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_copy_whole_image :: proc(
		p_image_ref: ImageRef,
		p_staging_buffer_ref: BufferRef,
		p_staging_buffer_offset: u32,
	) {

		image := &g_resources.images[image_get_idx(p_image_ref)]
		backend_image := &g_resources.backend_images[image_get_idx(p_image_ref)]
		backend_buffer := &g_resources.backend_buffers[buffer_get_idx(p_staging_buffer_ref)]

		image_copy := vk.BufferImageCopy {
			bufferOffset = vk.DeviceSize(p_staging_buffer_offset),
			imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
			imageExtent = vk.Extent3D {
				width = image.desc.dimensions.x,
				height = image.desc.dimensions.y,
				depth = 1,
			},
		}

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buffer_ref)]
		vk_cmd_buff := cmd_buffer.vk_cmd_buff

		if is_async_transfer_enabled() {
			vk_cmd_buff = frame_transfer_cmd_buffer_post_graphics_get()
		}

		vk.CmdCopyBufferToImage(
			vk_cmd_buff,
			backend_buffer.vk_buffer,
			backend_image.vk_image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&image_copy,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_issue_image_copies :: proc(
		p_image_ref: ImageRef,
		p_current_mip: u32,
		p_staging_buffer_ref: BufferRef,
		p_size: glsl.uvec2,
		p_mip_region_copies: [dynamic]ImageMipRegionCopy,
	) {

		temp_arena := common.Arena{}
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		buffer_image_copies := make(
			[]vk.BufferImageCopy,
			len(p_mip_region_copies),
			temp_arena.allocator,
		)

		image_idx := image_get_idx(p_image_ref)
		backend_image := &g_resources.backend_images[image_idx]

		backend_buffer := &g_resources.backend_buffers[buffer_get_idx(p_staging_buffer_ref)]

		for mip_region_copy, i in p_mip_region_copies {
			buffer_image_copies[i] = vk.BufferImageCopy {
				bufferOffset = vk.DeviceSize(mip_region_copy.staging_buffer_offset),
				imageOffset = vk.Offset3D {
					i32(mip_region_copy.offset.x),
					i32(mip_region_copy.offset.y),
					0,
				},
				imageSubresource = {
					aspectMask = {.COLOR},
					baseArrayLayer = 0,
					layerCount = 1,
					mipLevel = u32(p_current_mip),
				},
				imageExtent = {width = p_size.x, height = p_size.y, depth = 1},
			}
		}


		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buffer_ref)]
		vk_cmd_buff := cmd_buffer.vk_cmd_buff

		if is_async_transfer_enabled() {
			vk_cmd_buff = frame_transfer_cmd_buffer_post_graphics_get()
		}

		vk.CmdCopyBufferToImage(
			vk_cmd_buff,
			backend_buffer.vk_buffer,
			backend_image.vk_image,
			.TRANSFER_DST_OPTIMAL,
			u32(len(buffer_image_copies)),
			&buffer_image_copies[0],
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_finish_image_copy :: proc(p_image_ref: ImageRef, p_mip: u32) {
		finished_upload := FinishedImageUpload {
			image_ref = p_image_ref,
			fence_idx = u8(get_frame_idx()),
			mip       = p_mip,
		}
		append(&INTERNAL.finished_image_uploads, finished_upload)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_finalize_async_image_copies :: proc() {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena, common.MEGABYTE)
		defer common.arena_delete(temp_arena)

		finished_image_uploads := make([dynamic]FinishedImageUpload, get_next_frame_allocator())
		unique_image_refs := make(
			map[ImageRef]u8,
			len(INTERNAL.finished_image_uploads),
			temp_arena.allocator,
		)

		upload_fences := G_RENDERER.frame_fences[:]
		
		// Uploads from frame 0 are synchronous, they're finialized in frame 1
		// so we need to check graphics queue fences, as it was used on frame 0 for uploads
		if is_async_transfer_enabled() && get_frame_id() > 1 {
			upload_fences = G_RENDERER.transfer_fences_post_graphics[:]
		}

		fence_statuses := make(
			[]vk.Result,
			len(G_RENDERER.transfer_fences_post_graphics),
			temp_arena.allocator,
		)
		for fence, i in upload_fences {
			fence_statuses[i] = vk.GetFenceStatus(G_RENDERER.device, fence)
		}

		for finished_upload in &INTERNAL.finished_image_uploads {

			if fence_statuses[finished_upload.fence_idx] != .SUCCESS {
				append(&finished_image_uploads, finished_upload)
				continue
			}

			unique_image_refs[finished_upload.image_ref] = 0

			image_idx := image_get_idx(finished_upload.image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			image.loaded_mips_mask |= (1 << finished_upload.mip)

			if image.desc.file_mapping.mapped_ptr == nil {
				delete(image.desc.data_per_mip[finished_upload.mip], image.desc.mip_data_allocator)
			}

			if finished_upload.mip == 0 {
				if image.desc.file_mapping.mapped_ptr == nil {
					delete(image.desc.data_per_mip, G_RENDERER_ALLOCATORS.main_allocator)
				} else if finished_upload.mip == 0 {
					common.unmap_file(image.desc.file_mapping)
					image.desc.file_mapping = {}
				}
			}


			cmd_buffer_ref := get_frame_cmd_buffer_ref()
			cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buffer_ref)]

			backend_image.vk_layouts[0][finished_upload.mip] = .SHADER_READ_ONLY_OPTIMAL

			to_sample_barrier := vk.ImageMemoryBarrier {
				sType = .IMAGE_MEMORY_BARRIER,
				oldLayout = .TRANSFER_DST_OPTIMAL,
				newLayout = .SHADER_READ_ONLY_OPTIMAL,
				srcAccessMask = {.TRANSFER_WRITE},
				image = backend_image.vk_image,
				subresourceRange = {
					aspectMask = {.COLOR},
					baseArrayLayer = 0,
					layerCount = image.desc.array_size,
					baseMipLevel = u32(finished_upload.mip),
					levelCount = 1,
				},
			}

			if is_async_transfer_enabled() {

				transfer_cmd_buff := frame_transfer_cmd_buffer_pre_graphics_get()
				to_sample_barrier.srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index
				to_sample_barrier.dstQueueFamilyIndex = G_RENDERER.queue_family_graphics_index

				// Relase the resource on transfer queue
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.TRANSFER},
					{.BOTTOM_OF_PIPE},
					nil,
					0,
					nil,
					0,
					nil,
					1,
					&to_sample_barrier,
				)

				// Clear access mask, the image hasn't been used on graphics queue yet
				to_sample_barrier.srcAccessMask = {}
				// Layout was changed by transfer queue already, so adjust accordingly
				to_sample_barrier.oldLayout = .SHADER_READ_ONLY_OPTIMAL
				// Update stages where it's going to be used
				to_sample_barrier.dstAccessMask = {.SHADER_READ}

				// Acquire barrier on graphics queue
				vk.CmdPipelineBarrier(
					cmd_buffer.vk_cmd_buff,
					{.TOP_OF_PIPE},
					{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
					nil,
					0,
					nil,
					0,
					nil,
					1,
					&to_sample_barrier,
				)

				continue
			}

			to_sample_barrier.dstAccessMask = {.SHADER_READ}

			vk.CmdPipelineBarrier(
				cmd_buffer.vk_cmd_buff,
				{.TRANSFER},
				{.VERTEX_SHADER, .FRAGMENT_SHADER, .COMPUTE_SHADER},
				nil,
				0,
				nil,
				0,
				nil,
				1,
				&to_sample_barrier,
			)
		}

		INTERNAL.finished_image_uploads = finished_image_uploads

		if len(unique_image_refs) == 0 {
			return
		}

		// Update the bindless array
		bindless_bind_group_idx := bind_group_get_idx(G_RENDERER.bindless_bind_group_ref)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make(
			[]vk.WriteDescriptorSet,
			len(unique_image_refs),
			temp_arena.allocator,
		)

		image_infos := make([]vk.DescriptorImageInfo, len(unique_image_refs), temp_arena.allocator)

		num_bindless_updates := 0

		for image_ref in unique_image_refs {
			image_idx := image_get_idx(image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			highest_loaded_mip := image_get_highest_loaded_mip(image_ref)

			if highest_loaded_mip < image.desc.mip_count {
				// Update the descriptor in the bindless array  if we have any consecutive mip chain loaded
				image_infos[num_bindless_updates] = vk.DescriptorImageInfo {
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
					imageView   = backend_image.vk_views[0][highest_loaded_mip],
				}
				descriptor_writes[num_bindless_updates] = vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					descriptorCount = 1,
					descriptorType  = .SAMPLED_IMAGE,
					dstSet          = bindless_bind_group.vk_descriptor_set,
					pImageInfo      = &image_infos[num_bindless_updates],
					dstArrayElement = image.bindless_idx,
					dstBinding      = u32(BindlessResourceSlot.TextureArray2D),
				}

				num_bindless_updates += 1
			}

		}

		vk.UpdateDescriptorSets(
			G_RENDERER.device,
			u32(num_bindless_updates),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_image_copy_content :: proc(
		p_cmd_buffer_ref: CommandBufferRef,
		p_src_image_ref: ImageRef,
		p_dst_image_ref: ImageRef,
	) {
		src_image := &g_resources.images[image_get_idx(p_src_image_ref)]
		dst_image := &g_resources.images[image_get_idx(p_dst_image_ref)]

		assert(src_image.desc.array_size == dst_image.desc.array_size)
		assert(src_image.desc.mip_count == dst_image.desc.mip_count)
		assert(src_image.desc.type == dst_image.desc.type)
		assert(src_image.desc.format == dst_image.desc.format)

		src_backend_image := &g_resources.backend_images[image_get_idx(p_src_image_ref)]
		dst_backend_image := &g_resources.backend_images[image_get_idx(p_dst_image_ref)]

		cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(p_cmd_buffer_ref)]

		src_image_layout := src_backend_image.vk_layouts[0][0]
		dst_image_layout := dst_backend_image.vk_layouts[0][0]

		// Make sure all subresources have the same layout (required by the copy)
		for layouts, i in src_backend_image.vk_layouts {
			for layout, j in layouts {
				assert(src_image_layout == layout)
				src_backend_image.vk_layouts[i][j] = .TRANSFER_SRC_OPTIMAL
			}
		}

		for layouts, i in dst_backend_image.vk_layouts {
			for layout, j in layouts {
				assert(dst_image_layout == layout)
				dst_backend_image.vk_layouts[i][j] = .TRANSFER_DST_OPTIMAL
			}
		}

		temp_arena := common.Arena{}
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		regions := make([dynamic]vk.ImageCopy, temp_arena.allocator)

		for layer in 0 ..< src_image.desc.array_size {
			for mip in 0 ..< src_image.desc.mip_count {
				region := vk.ImageCopy {
					extent = vk.Extent3D {
						src_image.desc.dimensions.x << mip,
						src_image.desc.dimensions.y << mip,
						src_image.desc.dimensions.z << mip,
					},
					srcSubresource = {
						aspectMask = vk_map_image_aspect(src_backend_image.aspect_mask),
						baseArrayLayer = layer,
						mipLevel = mip,
						layerCount = 1,
					},
					dstSubresource = {
						aspectMask = vk_map_image_aspect(dst_backend_image.aspect_mask),
						baseArrayLayer = layer,
						mipLevel = mip,
						layerCount = 1,
					},
				}

				append(&regions, region)

			}
		}

		is_depth_image :=
			src_image.desc.format > .DepthFormatsStart && src_image.desc.format < .DepthFormatsEnd

		src_image_barrier := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			dstAccessMask = {.TRANSFER_READ},
			srcAccessMask = vk_resolve_access_from_layout(src_image_layout),
			image = src_backend_image.vk_image,
			newLayout = .TRANSFER_SRC_OPTIMAL,
			oldLayout = src_image_layout,
			subresourceRange = {
				aspectMask = vk.ImageAspectFlags{.DEPTH} if is_depth_image else {.COLOR},
				layerCount = src_image.desc.array_size,
				levelCount = src_image.desc.mip_count,
			},
		}

		dst_image_barrier := vk.ImageMemoryBarrier {
			sType = .IMAGE_MEMORY_BARRIER,
			dstAccessMask = {.TRANSFER_WRITE},
			srcAccessMask = vk_resolve_access_from_layout(dst_image_layout),
			image = dst_backend_image.vk_image,
			newLayout = .TRANSFER_DST_OPTIMAL,
			oldLayout = dst_image_layout,
			subresourceRange = {
				aspectMask = vk.ImageAspectFlags{.DEPTH} if is_depth_image else {.COLOR},
				layerCount = dst_image.desc.array_size,
				levelCount = dst_image.desc.mip_count,
			},
		}

		image_barriers := []vk.ImageMemoryBarrier{src_image_barrier, dst_image_barrier}

		vk.CmdPipelineBarrier(
			cmd_buffer.vk_cmd_buff,
			{.COMPUTE_SHADER, .COLOR_ATTACHMENT_OUTPUT, .LATE_FRAGMENT_TESTS},
			{.TRANSFER},
			{},
			0,
			nil,
			0,
			nil,
			u32(len(image_barriers)),
			raw_data(image_barriers),
		)

		vk.CmdCopyImage(
			cmd_buffer.vk_cmd_buff,
			src_backend_image.vk_image,
			.TRANSFER_SRC_OPTIMAL,
			dst_backend_image.vk_image,
			.TRANSFER_DST_OPTIMAL,
			u32(len(regions)),
			raw_data(regions),
		)
	}

	//---------------------------------------------------------------------------//
}
