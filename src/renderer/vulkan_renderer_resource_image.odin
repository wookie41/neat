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
		.OneDimensional   = vk.ImageViewType.D1_ARRAY,
		.TwoDimensional   = vk.ImageViewType.D2_ARRAY,
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
	backend_init_images :: proc() {
		INTERNAL.bindless_array_updates = make([dynamic]BindlessArrayUpdate)
		INTERNAL.finished_image_uploads = make([dynamic]FinishedImageUpload, get_frame_allocator())
		INTERNAL.default_image_ref = InvalidImageRef
	}

	@(private)
	backend_create_texture_image :: proc(p_image_ref: ImageRef) -> bool {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena, common.MEGABYTE)
		defer common.arena_delete(temp_arena)

		image_idx := get_image_idx(p_image_ref)

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
		if  image.desc.array_size > 1 {
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

		assert(image.desc.array_size == 0)

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

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_swap_images :: proc() {

		// If those images are already created, this means that the swapchain is getting recreated
		is_recreating_swapchain := len(G_RENDERER.swap_image_refs) > 0

		if is_recreating_swapchain == false {
			G_RENDERER.swap_image_refs = make(
				[]ImageRef,
				u32(len(G_RENDERER.swapchain_images)),
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			for _, i in G_RENDERER.swap_image_refs {
				G_RENDERER.swap_image_refs[i] = allocate_image_ref(common.create_name("SwapImage"))
			}
		}

		for vk_swap_image, i in G_RENDERER.swapchain_images {
			ref := G_RENDERER.swap_image_refs[i]
			image_idx := get_image_idx(ref)

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
	backend_create_image :: proc(p_image_ref: ImageRef) -> (res: bool) {

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		image_idx := get_image_idx(p_image_ref)
		image := &g_resources.images[image_idx]
		image_backend := &g_resources.backend_images[image_idx]

		image_type := vk.ImageType.D1
		#partial switch image.desc.type {
		case .TwoDimensional:
			image_type = .D2
		case .ThreeDimensional:
			image_type = .D3
		}

		usage := vk.ImageUsageFlags{}
		aspect_mask := vk.ImageAspectFlags{}

		if image.desc.format > .DepthFormatsStart && image.desc.format < .DepthFormatsEnd {
			usage += {.DEPTH_STENCIL_ATTACHMENT}
			aspect_mask += {.DEPTH}

			if image.desc.format > .DepthStencilFormatsStart &&
			   image.desc.format < .DepthStencilFormatsEnd {
				aspect_mask += {.STENCIL}
			}

		} else {
			aspect_mask += {.COLOR}
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
				aspectMask = aspect_mask,
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
					aspectMask = aspect_mask,
					levelCount = 1,
					layerCount = image.desc.mip_count,
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
						aspectMask = aspect_mask,
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

		return true
	}

	//---------------------------------------------------------------------------//

	backend_destroy_image :: proc(p_image_ref: ImageRef) {
		img_idx := get_image_idx(p_image_ref)
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
	backend_batch_update_bindless_array_entries :: proc() {
		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena)
		defer common.arena_delete(temp_arena)

		num_writes := len(INTERNAL.bindless_array_updates)
		if num_writes == 0 {
			return
		}

		bindless_bind_group_idx := get_bind_group_idx(G_RENDERER.bindless_bind_group_ref)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make([]vk.WriteDescriptorSet, u32(num_writes), temp_arena.allocator)

		image_infos := make([]vk.DescriptorImageInfo, u32(num_writes), temp_arena.allocator)

		if INTERNAL.default_image_ref == InvalidImageRef {
			INTERNAL.default_image_ref = find_image("DefaultImage")
		}

		backend_default_image := &g_resources.backend_images[get_image_idx(INTERNAL.default_image_ref)]

		for bindless_update, i in INTERNAL.bindless_array_updates {

			image_idx := get_image_idx(bindless_update.image_ref)
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

		image_idx := get_image_idx(p_ref)
		image := &g_resources.images[image_idx]
		backend_image := &g_resources.backend_images[image_idx]

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

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			transfer_cmd_buff := get_frame_transfer_cmd_buffer_post_graphics()

			vk.CmdPipelineBarrier(
				transfer_cmd_buff,
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

			return
		}

		cmd_buffer_ref := get_frame_cmd_buffer_ref()
		cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]

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

		image_idx := get_image_idx(p_image_ref)
		backend_image := &g_resources.backend_images[image_idx]

		backend_buffer := &g_resources.backend_buffers[get_buffer_idx(p_staging_buffer_ref)]

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
		cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]
		vk_cmd_buff := cmd_buffer.vk_cmd_buff

		if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
			vk_cmd_buff = get_frame_transfer_cmd_buffer_post_graphics()
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
		unique_image_refs := make_map(
			map[ImageRef]u8,
			len(INTERNAL.finished_image_uploads),
			temp_arena.allocator,
		)

		for finished_upload in &INTERNAL.finished_image_uploads {

			upload_done_fence := G_RENDERER.frame_fences[finished_upload.fence_idx]
			if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
				upload_done_fence =
					G_RENDERER.transfer_fences_post_graphics[finished_upload.fence_idx]
			}


			if vk.GetFenceStatus(G_RENDERER.device, upload_done_fence) != .SUCCESS {
				append(&finished_image_uploads, finished_upload)
				continue
			}

			unique_image_refs[finished_upload.image_ref] = 0

			image_idx := get_image_idx(finished_upload.image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			image.loaded_mips_mask |= (1 << finished_upload.mip)

			if image.desc.file_mapping.mapped_ptr == nil {
				delete(image.desc.data_per_mip[finished_upload.mip], image.desc.mip_data_allocator)
			} else if finished_upload.mip == 0 {
				common.unmap_file(image.desc.file_mapping)
				image.desc.file_mapping = {}
			}

			cmd_buffer_ref := get_frame_cmd_buffer_ref()
			cmd_buffer := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(cmd_buffer_ref)]

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

			if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {

				transfer_cmd_buff := get_frame_transfer_cmd_buffer_pre_graphics()
				to_sample_barrier.srcQueueFamilyIndex = G_RENDERER.queue_family_transfer_index
				to_sample_barrier.dstQueueFamilyIndex = G_RENDERER.queue_family_graphics_index

				// Release
				vk.CmdPipelineBarrier(
					transfer_cmd_buff,
					{.TRANSFER},
					{.TOP_OF_PIPE},
					nil,
					0,
					nil,
					0,
					nil,
					1,
					&to_sample_barrier,
				)

				// Acquire
				vk.CmdPipelineBarrier(
					cmd_buffer.vk_cmd_buff,
					{.TRANSFER},
					{.TOP_OF_PIPE},
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
		bindless_bind_group_idx := get_bind_group_idx(G_RENDERER.bindless_bind_group_ref)
		bindless_bind_group := &g_resources.backend_bind_groups[bindless_bind_group_idx]

		descriptor_writes := make(
			[]vk.WriteDescriptorSet,
			len(unique_image_refs),
			temp_arena.allocator,
		)

		image_infos := make([]vk.DescriptorImageInfo, len(unique_image_refs), temp_arena.allocator)

		num_bindless_updates := 0

		for image_ref in unique_image_refs {
			image_idx := get_image_idx(image_ref)
			image := &g_resources.images[image_idx]
			backend_image := &g_resources.backend_images[image_idx]

			mip_count := image.desc.mip_count
			loaded_mips_mask := ~image.loaded_mips_mask
			loaded_mips_mask = loaded_mips_mask << (16 - mip_count)
			highest_loaded_mip :=
				mip_count - min(u32(intrinsics.count_leading_zeros(loaded_mips_mask)), mip_count)

			if highest_loaded_mip < image.desc.mip_count {
				// Update the descriptor in the bindless array 
				// if we have any  consecutive mip chain loaded
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
}
