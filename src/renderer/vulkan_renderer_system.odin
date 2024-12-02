package renderer

//---------------------------------------------------------------------------//

import "base:runtime"
import "core:c"
import "core:log"

import vma "../third_party/vma"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

import "../common"

//--------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	@(private)
	BackendInitOptions :: struct {
		window: ^sdl.Window,
	}

	//---------------------------------------------------------------------------//

	BackendMiscFlagBits :: enum u32 {
		WINDOW_RESIZED,
	}

	BackendMiscFlags :: distinct bit_set[BackendMiscFlagBits;u32]

	//---------------------------------------------------------------------------//

	@(private)
	BackendRendererState :: struct {
		window:                        ^sdl.Window,
		windowID:                      u32,
		instance:                      vk.Instance,
		physical_device:               vk.PhysicalDevice,
		surface_capabilities:          vk.SurfaceCapabilitiesKHR,
		device_properties:             vk.PhysicalDeviceProperties,
		swapchain_formats:             []vk.SurfaceFormatKHR,
		swapchain_present_modes:       []vk.PresentModeKHR,
		queue_family_graphics_index:   u32,
		queue_family_present_index:    u32,
		queue_family_compute_index:    u32,
		queue_family_transfer_index:   u32,
		device:                        vk.Device,
		graphics_queue:                vk.Queue,
		present_queue:                 vk.Queue,
		compute_queue:                 vk.Queue,
		transfer_queue:                vk.Queue,
		surface:                       vk.SurfaceKHR,
		swapchain_format:              vk.SurfaceFormatKHR,
		present_mode:                  vk.PresentModeKHR,
		swap_extent:                   vk.Extent2D,
		swapchain:                     vk.SwapchainKHR,
		swapchain_images:              [dynamic]vk.Image,
		swapchain_image_views:         [dynamic]vk.ImageView,
		render_finished_semaphores:    [dynamic]vk.Semaphore,
		image_available_semaphores:    [dynamic]vk.Semaphore,
		frame_fences:                  [dynamic]vk.Fence,
		vma_allocator:                 vma.Allocator,
		misc_flags:                    BackendMiscFlags,
		swap_img_idx:                  u32,
		transfer_fences_pre_graphics:  []vk.Fence,
		transfer_fences_post_graphics: []vk.Fence,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init :: proc(p_options: InitOptions) -> bool {

		device_extensions := []struct {
			name:     cstring,
			required: bool,
		} {
			{name = vk.KHR_SWAPCHAIN_EXTENSION_NAME, required = true},
			{name = vk.KHR_MAINTENANCE1_EXTENSION_NAME, required = true},
			{name = vk.KHR_MAINTENANCE3_EXTENSION_NAME, required = true},
			{name = vk.EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME, required = true},
			{name = vk.EXT_DEBUG_MARKER_EXTENSION_NAME, required = false},
		}


		G_RENDERER.window = p_options.window
		G_RENDERER.windowID = sdl.GetWindowID(p_options.window)

		// Load the base vulkan procedures
		vk.load_proc_addresses(sdl.Vulkan_GetVkGetInstanceProcAddr())

		temp_arena: common.Arena
		common.temp_arena_init(&temp_arena, common.MEGABYTE)
		defer common.arena_delete(temp_arena)

		// Create Vulkan Instance
		{
			using G_RENDERER
			using G_RENDERER_ALLOCATORS

			// Specify a list of required extensions and layers
			instance_extensions := make([dynamic]cstring, temp_arena.allocator)
			defer delete(instance_extensions)
			required_layers := make([dynamic]cstring, temp_arena.allocator)
			defer delete(required_layers)

			// Add SDL extensions
			{
				extension_count: c.uint
				sdl.Vulkan_GetInstanceExtensions(window, &extension_count, nil)
				resize(&instance_extensions, int(extension_count))
				sdl.Vulkan_GetInstanceExtensions(
					window,
					&extension_count,
					raw_data(instance_extensions),
				)
			}

			// Add a couple of debug extensions and layers
			when ODIN_DEBUG {
				append(
					&instance_extensions,
					vk.EXT_DEBUG_REPORT_EXTENSION_NAME,
					vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
				)
			}

			// Bindless support
			append(&instance_extensions, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)

			// Check the required extensions and layers are supported
			supported_extensions := make([dynamic]vk.ExtensionProperties, temp_arena.allocator)

			{
				extension_count: u32
				vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
				resize(&supported_extensions, int(extension_count))
				vk.EnumerateInstanceExtensionProperties(
					nil,
					&extension_count,
					raw_data(supported_extensions),
				)
			}

			supported_layers := make([dynamic]vk.LayerProperties, temp_arena.allocator)
			defer delete(supported_layers)
			{
				layer_count: u32
				vk.EnumerateInstanceLayerProperties(&layer_count, nil)
				resize(&supported_layers, int(layer_count))
				vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(supported_layers))
			}

			for required in instance_extensions {
				contains := false
				for &supported in supported_extensions {
					name := transmute(cstring)&supported.extensionName
					if runtime.cstring_eq(name, required) {
						contains = true
						break
					}
				}
				if !contains {
					log.errorf("Extension '%s' is not in extensions list\n", required)
					return false
				}
			}

			for required in required_layers {
				contains := false
				for &supported in supported_layers {
					name := transmute(cstring)&supported.layerName
					if runtime.cstring_eq(name, required) {
						contains = true
						break
					}
				}
				if !contains {
					log.errorf("Layer '%s' is not in layers list\n", required)
					return false
				}
			}

			app_info := vk.ApplicationInfo {
				sType              = .APPLICATION_INFO,
				pApplicationName   = "neat-renderer",
				applicationVersion = vk.MAKE_VERSION(0, 0, 1),
				pEngineName        = "neat",
				engineVersion      = vk.MAKE_VERSION(0, 0, 1),
				apiVersion         = vk.API_VERSION_1_3,
			}


			instance_info := vk.InstanceCreateInfo {
				sType                   = .INSTANCE_CREATE_INFO,
				enabledExtensionCount   = u32(len(instance_extensions)),
				ppEnabledExtensionNames = raw_data(instance_extensions),
				enabledLayerCount       = u32(len(required_layers)),
				ppEnabledLayerNames     = raw_data(required_layers),
				pApplicationInfo        = &app_info,
			}

			if vk.CreateInstance(&instance_info, nil, &instance) != .SUCCESS {
				log.error("Failed to create Vulkan instance")
				return false
			}
		}

		// Load the rest of the functions
		vk.load_proc_addresses(G_RENDERER.instance)

		// Create a single surface for now
		if !sdl.Vulkan_CreateSurface(G_RENDERER.window, G_RENDERER.instance, &G_RENDERER.surface) {
			log.error("SDL couldn't create vulkan surface")
			return false
		}

		enabled_device_extensions := make([dynamic]cstring, temp_arena.allocator)

		// Create physical device
		{
			using G_RENDERER
			using G_RENDERER_ALLOCATORS

			physical_device_count: u32
			vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil)
			if physical_device_count == 0 {
				log.error("No physical device with Vulkan support detected")
				return false
			}

			physical_devices := make(
				[]vk.PhysicalDevice,
				physical_device_count,
				temp_arena.allocator,
			)

			vk.EnumeratePhysicalDevices(
				instance,
				&physical_device_count,
				raw_data(physical_devices),
			)

			// Find a suitable device
			for pd in &physical_devices {

				clear(&enabled_device_extensions)

				device_props: vk.PhysicalDeviceProperties
				vk.GetPhysicalDeviceProperties(pd, &device_props)
				log.infof("Checking device %s...\n ", device_props.deviceName)

				// Check extension compatibility
				extension_count: u32
				vk.EnumerateDeviceExtensionProperties(pd, nil, &extension_count, nil)

				extensions := make([]vk.ExtensionProperties, extension_count, temp_arena.allocator)
				vk.EnumerateDeviceExtensionProperties(
					pd,
					nil,
					&extension_count,
					raw_data(extensions),
				)

				device_has_all_required_extension := true
				for re, _ in &device_extensions {
					contains := false
					for &e in extensions {
						name := transmute(cstring)&e.extensionName
						if runtime.cstring_eq(re.name, name) {

							if re.name == vk.EXT_DEBUG_MARKER_EXTENSION_NAME {
								G_RENDERER.debug_mode = true
							}

							append(&enabled_device_extensions, re.name)
							contains = true
							break
						}
					}
					if !contains {
						if re.required {
							log.infof(
								"Device %s not suitable, missing extension %s\n",
								device_props.deviceName,
								re,
							)

							device_has_all_required_extension = false
							break
						}
					}
				}
				if !device_has_all_required_extension {
					continue
				}

				// surface capabilities
				capabilities: vk.SurfaceCapabilitiesKHR
				vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(pd, surface, &capabilities)

				// supported formats
				format_count: u32
				vk.GetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &format_count, nil)
				if format_count == 0 {
					continue
				}

				formats := make(
					[]vk.SurfaceFormatKHR,
					int(format_count),
					G_RENDERER_ALLOCATORS.main_allocator,
				)
				vk.GetPhysicalDeviceSurfaceFormatsKHR(
					pd,
					surface,
					&format_count,
					raw_data(formats),
				)

				// supported present modes
				present_mode_count: u32
				vk.GetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &present_mode_count, nil)
				if present_mode_count == 0 {
					continue
				}

				present_modes := make(
					[]vk.PresentModeKHR,
					int(present_mode_count),
					G_RENDERER_ALLOCATORS.main_allocator,
				)
				vk.GetPhysicalDeviceSurfacePresentModesKHR(
					pd,
					surface,
					&present_mode_count,
					raw_data(present_modes),
				)

				// check the device queue families
				queue_family_count: u32
				vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, nil)

				queue_families := make(
					[]vk.QueueFamilyProperties,
					int(queue_family_count),
					temp_arena.allocator,
				)

				vk.GetPhysicalDeviceQueueFamilyProperties(
					pd,
					&queue_family_count,
					raw_data(queue_families),
				)

				graphics_index := -1
				present_index := -1
				compute_index := -1
				transfer_index := -1
				for qf, i in queue_families {
					if graphics_index == -1 && .GRAPHICS in qf.queueFlags {
						graphics_index = i
						// Use the graphics queue as compute and transfer only if the GPU 
						// doesn't have seprate queues for those purposes or we didn't find one yet
						if compute_index == -1 && .COMPUTE in qf.queueFlags {
							compute_index = i
						}
						if transfer_index == -1 && .TRANSFER in qf.queueFlags {
							transfer_index = i
						}
					} else if .COMPUTE in qf.queueFlags {
						// Found a compute-only queue
						compute_index = i
					} else if .TRANSFER in qf.queueFlags {
						// Found a transfer-only queue
						transfer_index = i
					}

					present_support: b32
					vk.GetPhysicalDeviceSurfaceSupportKHR(pd, u32(i), surface, &present_support)
					if present_index == -1 && present_support {
						present_index = i
					}
				}

				if graphics_index == -1 ||
				   present_index == -1 ||
				   compute_index == -1 ||
				   transfer_index == -1 {
					continue
				}

				log.infof(
					"Found device %s, queues indices:\n - graphics: %d\n - present: %d\n - compute: %d\n - transfer: %d",
					device_props.deviceName,
					graphics_index,
					present_index,
					compute_index,
					transfer_index,
				)

				if graphics_index != -1 &&
				   present_index != -1 &&
				   compute_index != -1 &&
				   transfer_index != -1 &&
				   device_props.deviceType != .CPU {

					log.infof("Picked device: %s\n ", device_props.deviceName)

					if device_props.deviceType == .INTEGRATED_GPU {
						G_RENDERER.gpu_device_flags += {.IntegratedGPU}
					}

					physical_device = pd
					surface_capabilities = capabilities
					swapchain_formats = formats
					swapchain_present_modes = present_modes
					queue_family_graphics_index = u32(graphics_index)
					queue_family_present_index = u32(present_index)
					queue_family_compute_index = u32(compute_index)
					queue_family_transfer_index = u32(transfer_index)

					if queue_family_transfer_index != queue_family_compute_index {
						G_RENDERER.gpu_device_flags += {.DedicatedTransferQueue}
					}

					if queue_family_compute_index != queue_family_compute_index {
						G_RENDERER.gpu_device_flags += {.DedicatedComputeQueue}
					}

					break
				}
			}

			if physical_device == nil {
				log.error("Suitable device not found")
				return false
			}

			vk.GetPhysicalDeviceProperties(physical_device, &device_properties)

			G_RENDERER.min_uniform_buffer_alignment = u32(
				device_properties.limits.minUniformBufferOffsetAlignment,
			)
		}

		// Create logical device for our queues (and the queues themselves)
		{
			using G_RENDERER
			using G_RENDERER_ALLOCATORS

			// Avoid creating duplicates
			queue_families := make(map[u32]int, 4, temp_arena.allocator)
			queue_families[queue_family_graphics_index] = 1
			queue_families[queue_family_present_index] = 1
			queue_families[queue_family_compute_index] = 1
			queue_families[queue_family_transfer_index] = 1

			queue_priorities := make([]f32, len(queue_families), temp_arena.allocator)

			for qfc in 0 ..< len(queue_families) {
				queue_families[u32(qfc)] = 1.0
			}

			queue_create_infos := make(
				[]vk.DeviceQueueCreateInfo,
				len(queue_families),
				temp_arena.allocator,
			)

			{
				idx := 0
				for family, count in &queue_families {
					queue_create_infos[idx] = vk.DeviceQueueCreateInfo {
						sType            = .DEVICE_QUEUE_CREATE_INFO,
						queueFamilyIndex = u32(family),
						queueCount       = u32(count),
						pQueuePriorities = raw_data(queue_priorities),
					}
					idx += 1
				}

			}

			device_features := vk.PhysicalDeviceFeatures{}
			device_features.samplerAnisotropy = true
			device_features.depthClamp = true

			robustness2_features := vk.PhysicalDeviceRobustness2FeaturesEXT {
				sType          = .PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
				nullDescriptor = true,
			}

			dynamic_rendering_fratures := vk.PhysicalDeviceDynamicRenderingFeatures {
				sType            = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
				dynamicRendering = true,
				pNext            = &robustness2_features,
			}

			descriptor_indexing_features := vk.PhysicalDeviceDescriptorIndexingFeaturesEXT {
				sType                                        = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT,
				shaderSampledImageArrayNonUniformIndexing    = true,
				runtimeDescriptorArray                       = true,
				descriptorBindingVariableDescriptorCount     = true,
				descriptorBindingSampledImageUpdateAfterBind = true,
				descriptorBindingPartiallyBound              = true,
				pNext                                        = &dynamic_rendering_fratures,
			}

			device_create_info := vk.DeviceCreateInfo {
				sType                   = .DEVICE_CREATE_INFO,
				queueCreateInfoCount    = u32(len(queue_create_infos)),
				pQueueCreateInfos       = raw_data(queue_create_infos),
				enabledExtensionCount   = u32(len(enabled_device_extensions)),
				ppEnabledExtensionNames = raw_data(enabled_device_extensions),
				pEnabledFeatures        = &device_features,
				pNext                   = &descriptor_indexing_features,
			}

			if result := vk.CreateDevice(physical_device, &device_create_info, nil, &device);
			   result != .SUCCESS {
				log.error("Couldn't create Vulkan device")
				return false
			}

			vk.GetDeviceQueue(device, u32(queue_family_graphics_index), 0, &graphics_queue)
			if graphics_queue == nil {
				log.error("Couldn't create device queue")
				return false
			}

			vk.GetDeviceQueue(device, u32(queue_family_present_index), 0, &present_queue)
			if present_queue == nil {
				log.error("Couldn't create present queue")
				return false
			}

			vk.GetDeviceQueue(device, u32(queue_family_compute_index), 0, &compute_queue)
			if compute_queue == nil {
				log.error("Couldn't create compute queue")
				return false
			}

			vk.GetDeviceQueue(device, u32(queue_family_transfer_index), 0, &transfer_queue)
			if transfer_queue == nil {
				log.error("Couldn't create transfer queue")
				return false
			}
		}

		// Load device function pointers
		vk.load_proc_addresses(G_RENDERER.device)

		// Get the swapchain working
		G_RENDERER.swapchain_images = make([dynamic]vk.Image)

		if create_swapchain() == false {
			return false
		}

		create_synchronization_primitives()

		// Init VMA
		{
			vulkan_functions := vma.create_vulkan_functions()
			create_info := vma.AllocatorCreateInfo {
				vulkanApiVersion = vk.API_VERSION_1_3,
				physicalDevice   = G_RENDERER.physical_device,
				device           = G_RENDERER.device,
				instance         = G_RENDERER.instance,
				pVulkanFunctions = &vulkan_functions,
			}
			if vma.create_allocator(&create_info, &G_RENDERER.vma_allocator) != .SUCCESS {
				log.error("Failed to create VMA allocator")
				return false
			}
		}

		return true
	}
	//---------------------------------------------------------------------------//
	@(private)
	deinit_backend :: proc() {
		using G_RENDERER
		vma.destroy_allocator(vma_allocator)
		for i in 0 ..< num_frames_in_flight {
			vk.DestroyFence(device, frame_fences[i], nil)
			vk.DestroySemaphore(device, render_finished_semaphores[i], nil)
			vk.DestroySemaphore(device, image_available_semaphores[i], nil)
		}
		for swap_image_view in swapchain_image_views {
			vk.DestroyImageView(device, swap_image_view, nil)
		}
		if swapchain != 0 {
			vk.DestroySwapchainKHR(device, swapchain, nil)
		}
		if device != nil {
			vk.DestroyDevice(device, nil)
		}
		if surface != vk.SurfaceKHR(0) {
			vk.DestroySurfaceKHR(instance, surface, nil)
		}
		if instance != nil {
			vk.DestroyInstance(instance, nil)
		}
		if window != nil {
			sdl.DestroyWindow(window)
		}
		sdl.Quit()
	}
}
//---------------------------------------------------------------------------//

@(private)
backend_wait_for_frame_resources :: proc() {
	frame_idx := get_frame_idx()

	vk.WaitForFences(G_RENDERER.device, 1, &G_RENDERER.frame_fences[frame_idx], true, max(u64))

	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_wait_for_transfer_resources()
	}
}

//---------------------------------------------------------------------------//

@(private)
backend_post_render :: proc() {

	swap_image_ref := G_RENDERER.swap_image_refs[G_RENDERER.swap_img_idx]
	swap_image := &g_resources.backend_images[get_image_idx(swap_image_ref)]

	backend_cmd_buff := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(get_frame_cmd_buffer_ref())]

	// Transition the swapchain to present 
	to_present_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = swap_image.vk_layouts[0][0],
		newLayout = .PRESENT_SRC_KHR,
		image = G_RENDERER.swapchain_images[G_RENDERER.swap_img_idx],
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		backend_cmd_buff.vk_cmd_buff,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_present_barrier,
	)
}

//---------------------------------------------------------------------------//

@(private)
backend_submit_current_frame :: proc() {

	backend_cmd_buff := &g_resources.backend_cmd_buffers[get_cmd_buffer_idx(get_frame_cmd_buffer_ref())]

	// Submit
	{
		vk.ResetFences(G_RENDERER.device, 1, &G_RENDERER.frame_fences[get_frame_idx()])

		submit_info := vk.SubmitInfo {
			sType                = .SUBMIT_INFO,
			pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
			commandBufferCount   = 1,
			pCommandBuffers      = &backend_cmd_buff.vk_cmd_buff,
			waitSemaphoreCount   = 1,
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &G_RENDERER.render_finished_semaphores[get_frame_idx()],
			pWaitSemaphores      = &G_RENDERER.image_available_semaphores[get_frame_idx()],
		}

		vk.QueueSubmit(
			G_RENDERER.graphics_queue,
			1,
			&submit_info,
			G_RENDERER.frame_fences[get_frame_idx()],
		)
	}

	// Present
	{
		present_info := vk.PresentInfoKHR {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &G_RENDERER.render_finished_semaphores[get_frame_idx()],
			swapchainCount     = 1,
			pSwapchains        = &G_RENDERER.swapchain,
			pImageIndices      = &G_RENDERER.swap_img_idx,
		}

		vk.QueuePresentKHR(G_RENDERER.present_queue, &present_info)
	}
}


@(private = "file")
create_swapchain :: proc(p_is_recreating: bool = false) -> bool {
	old_format := G_RENDERER.swapchain_format
	// find ideal format for swapchain
	{
		ideal_format := false

		for format in &G_RENDERER.swapchain_formats {
			if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
				G_RENDERER.swapchain_format = format
				ideal_format = true
				break
			}
		}

		if !ideal_format {
			G_RENDERER.swapchain_format = G_RENDERER.swapchain_formats[0]
		}
	}

	old_present_mode := G_RENDERER.present_mode
	// find ideal mode for presentation
	{
		ideal_present_mode := false
		for present_mode in &G_RENDERER.swapchain_present_modes {
			if present_mode == .MAILBOX {
				G_RENDERER.present_mode = present_mode
				ideal_present_mode = true
				break
			}
		}
		if !ideal_present_mode {
			G_RENDERER.present_mode = .FIFO
		}
	}

	if p_is_recreating &&
	   (old_present_mode != G_RENDERER.present_mode || old_format != G_RENDERER.swapchain_format) {
		log.fatal("Changing swapchain format/presnet mode on runtime is currently not supported")
	}
	// find ideal swap extent from capabilities or sdl2
	{
		G_RENDERER.swap_extent = G_RENDERER.surface_capabilities.currentExtent
		if G_RENDERER.swap_extent.width == max(u32) {
			width, height: c.int
			sdl.Vulkan_GetDrawableSize(G_RENDERER.window, &width, &height)
			G_RENDERER.swap_extent.width = clamp(
				u32(width),
				G_RENDERER.surface_capabilities.minImageExtent.width,
				G_RENDERER.surface_capabilities.maxImageExtent.width,
			)
			G_RENDERER.swap_extent.height = clamp(
				u32(height),
				G_RENDERER.surface_capabilities.minImageExtent.height,
				G_RENDERER.surface_capabilities.maxImageExtent.height,
			)
		}

		// prefer min + 1 images on the swapchain but no more than max
		swap_images_count := G_RENDERER.surface_capabilities.minImageCount + 1
		if G_RENDERER.surface_capabilities.maxImageCount > 0 &&
		   swap_images_count > G_RENDERER.surface_capabilities.maxImageCount {
			swap_images_count = G_RENDERER.surface_capabilities.maxImageCount
		}
		resize(&G_RENDERER.swapchain_images, int(swap_images_count))
		resize(&G_RENDERER.swapchain_image_views, int(swap_images_count))
	}

	// Create the swapchain
	{
		// handle different queue families
		queue_families := []u32 {
			u32(G_RENDERER.queue_family_graphics_index),
			u32(G_RENDERER.queue_family_present_index),
		}
		create_info := vk.SwapchainCreateInfoKHR {
			sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
			surface               = G_RENDERER.surface,
			minImageCount         = u32(len(G_RENDERER.swapchain_images)),
			imageFormat           = G_RENDERER.swapchain_format.format,
			imageColorSpace       = G_RENDERER.swapchain_format.colorSpace,
			imageExtent           = G_RENDERER.swap_extent,
			imageArrayLayers      = 1,
			imageUsage            = {.COLOR_ATTACHMENT},
			imageSharingMode      = .EXCLUSIVE,
			preTransform          = G_RENDERER.surface_capabilities.currentTransform,
			compositeAlpha        = {.OPAQUE},
			presentMode           = G_RENDERER.present_mode,
			clipped               = true,
			queueFamilyIndexCount = 1,
			pQueueFamilyIndices   = raw_data(queue_families),
		}
		if G_RENDERER.queue_family_graphics_index != G_RENDERER.queue_family_present_index {
			create_info.imageSharingMode = .CONCURRENT
			create_info.queueFamilyIndexCount = 2
		}

		// finally the swapchain
		if vk.CreateSwapchainKHR(G_RENDERER.device, &create_info, nil, &G_RENDERER.swapchain) !=
		   .SUCCESS {
			log.error("Couldn't create swapchain")
			return false
		}
	}

	// Get swap images
	{
		swap_images_count := u32(len(G_RENDERER.swapchain_images))
		vk.GetSwapchainImagesKHR(
			G_RENDERER.device,
			G_RENDERER.swapchain,
			&swap_images_count,
			raw_data(G_RENDERER.swapchain_images),
		)

		// Create image views for each image
		for i in 0 ..< len(G_RENDERER.swapchain_image_views) {
			create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = G_RENDERER.swapchain_images[i],
				viewType = .D2,
				format = G_RENDERER.swapchain_format.format,
				components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			}

			if vk.CreateImageView(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &G_RENDERER.swapchain_image_views[i],
			   ) !=
			   .SUCCESS {
				log.error("Error creating image view\n")
				return false
			}
		}
	}

	return true
}

create_synchronization_primitives :: proc() {
	using G_RENDERER

	num_frames_in_flight = u32(clamp(MAX_NUM_FRAMES_IN_FLIGHT, 0, len(swapchain_images)))

	resize(&render_finished_semaphores, int(num_frames_in_flight))
	resize(&image_available_semaphores, int(num_frames_in_flight))

	resize(&frame_fences, int(num_frames_in_flight))

	fence_create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	for i in 0 ..< num_frames_in_flight {
		vk.CreateFence(device, &fence_create_info, nil, &frame_fences[i])
		vk.CreateSemaphore(device, &semaphore_create_info, nil, &render_finished_semaphores[i])
		vk.CreateSemaphore(device, &semaphore_create_info, nil, &image_available_semaphores[i])
	}
}

recreate_swapchain :: proc() {
	using G_RENDERER

	// Refresh capabilties, formats and present modes
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil)
	if format_count == 0 {
		log.fatal("Can't recreate a swapchain - no formats")
	}

	formats := make([]vk.SurfaceFormatKHR, int(format_count))
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&format_count,
		raw_data(formats),
	)

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)
	if present_mode_count == 0 {
		log.fatal("Can't recreate a swapchain - no presnet modes")
	}

	present_modes := make([]vk.PresentModeKHR, int(present_mode_count))
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		raw_data(present_modes),
	)

	delete(swapchain_formats)
	delete(swapchain_present_modes)

	swapchain_formats = formats
	swapchain_present_modes = present_modes

	clear(&swapchain_images)
	clear(&swapchain_image_views)

	// @TODO Make it better, use pOldSwapchain when recreating the swapchain 
	vk.DeviceWaitIdle(device)

	for image_view in swapchain_image_views {
		vk.DestroyImageView(device, image_view, nil)
	}

	for _, i in frame_fences {
		vk.DestroyFence(device, frame_fences[i], nil)
		vk.DestroySemaphore(device, render_finished_semaphores[i], nil)
		vk.DestroySemaphore(device, image_available_semaphores[i], nil)
	}

	vk.DestroySwapchainKHR(device, swapchain, nil)

	if create_swapchain(true) == false {
		log.fatal("Failed to recreate the swapchain")
	}

	create_synchronization_primitives()
}

//---------------------------------------------------------------------------//

backend_handler_on_window_resized :: proc(p_event: WindowResizedEvent) {
	if p_event.windowID == G_RENDERER.windowID {
		G_RENDERER.misc_flags += {.WINDOW_RESIZED}
	}
}

//---------------------------------------------------------------------------//

@(private)
backend_begin_frame :: proc() {

	frame_idx := get_frame_idx()

	// Wait until frame resources will not be used anymore
	// @TODO Move this after recording the command buffer to save some performance
	acquire_result := vk.AcquireNextImageKHR(
		G_RENDERER.device,
		G_RENDERER.swapchain,
		c.UINT64_MAX,
		G_RENDERER.image_available_semaphores[frame_idx],
		0,
		&G_RENDERER.swap_img_idx,
	)
	// Check if we need to recreate the swapchain
	should_recreate_swapchain := .WINDOW_RESIZED in G_RENDERER.misc_flags
	G_RENDERER.misc_flags -= {.WINDOW_RESIZED}

	if acquire_result != .SUCCESS {
		if acquire_result == .ERROR_OUT_OF_DATE_KHR || acquire_result == .SUBOPTIMAL_KHR {
			should_recreate_swapchain |= true
		}
	}

	if should_recreate_swapchain {
		recreate_swapchain()
		create_swap_images()

		vk.AcquireNextImageKHR(
			G_RENDERER.device,
			G_RENDERER.swapchain,
			c.UINT64_MAX,
			G_RENDERER.image_available_semaphores[frame_idx],
			0,
			&G_RENDERER.swap_img_idx,
		)

		vk.ResetFences(G_RENDERER.device, 1, &G_RENDERER.frame_fences[frame_idx])

		return
	}

	// We have to put the current swap image in the undefined state, so proper barriers are issued
	{
		swap_image_ref := G_RENDERER.swap_image_refs[G_RENDERER.swap_img_idx]
		image_backend := &g_resources.backend_images[get_image_idx(swap_image_ref)]
		image_backend.vk_layouts[0][0] = .UNDEFINED
	}


	if .DedicatedTransferQueue in G_RENDERER.gpu_device_flags {
		backend_buffer_upload_start_async_cmd_buffer_pre_graphics()
		backend_buffer_upload_start_async_cmd_buffer_post_graphics()
	}
}

//---------------------------------------------------------------------------//

@(private)
get_queue_family_index :: proc(p_device_queue_type: DeviceQueueType) -> (queue_family_index: u32) {

	switch p_device_queue_type {
	case .Graphics:
		queue_family_index = G_RENDERER.queue_family_graphics_index
	case .Compute:
		queue_family_index = G_RENDERER.queue_family_compute_index
	case .Transfer:
		queue_family_index = G_RENDERER.queue_family_transfer_index
	case:
		assert(false)
	}

	return
}

//---------------------------------------------------------------------------//
