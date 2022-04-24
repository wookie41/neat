package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:c"
	import "core:mem"
	import "core:log"
	import "core:slice"

	import sdl "vendor:sdl2"
	import vk "vendor:vulkan"

	import  "../common"

	//---------------------------------------------------------------------------//

	@(private)
	BackendInitOptions :: struct {
		window: ^sdl.Window,
	}

	//---------------------------------------------------------------------------//

	@(private)
	BackendRendererState :: struct {
		window:                      ^sdl.Window,
		instance:                    vk.Instance,
		physical_device:             vk.PhysicalDevice,
		device_capabilities:         vk.SurfaceCapabilitiesKHR,
		device_formats:              []vk.SurfaceFormatKHR,
		device_present_modes:        []vk.PresentModeKHR,
		queue_family_graphics_index: u32,
		queue_family_present_index:  u32,
		queue_family_compute_index:  u32,
		supports_compute:            bool,
		device:                      vk.Device,
		graphics_queue:              vk.Queue,
		present_queue:               vk.Queue,
		compute_queue:               vk.Queue,
		surface:                     vk.SurfaceKHR,
		surface_format:              vk.SurfaceFormatKHR,
		present_mode:                vk.PresentModeKHR,
		swap_extent:                 vk.Extent2D,
		swapchain:                   vk.SwapchainKHR,
		swapchain_images:            [dynamic]vk.Image,
		swapchain_image_views:       [dynamic]vk.ImageView,
		render_finished_semaphores:  [dynamic]vk.Semaphore,
		image_available_semaphores:  [dynamic]vk.Semaphore,
		frame_fences:                [dynamic]vk.Fence,
		num_frames_in_flight:        u32,
		frame_idx:                   u32,
	}

	@(private = "file")
	g_log: log.Logger

	//---------------------------------------------------------------------------//

	@(private)
	backend_init :: proc(p_options: InitOptions) -> bool {

		device_extensions := []cstring{"VK_KHR_swapchain"}

		context.logger = G_RENDERER_LOG

		G_RENDERER.allocator = p_options.allocator
		G_RENDERER.window = p_options.window
		G_RENDERER.frame_idx = 0

		mem.init_arena(
			&G_RENDERER.temp_arena,
			make([]byte, common.MEGABYTE * 4, p_options.allocator),
		)
		G_RENDERER.temp_arena_allocator = mem.arena_allocator(&G_RENDERER.temp_arena)

		// Load the base vulkan procedures
		vk.load_proc_addresses(sdl.Vulkan_GetVkGetInstanceProcAddr())

		// Create Vulkan Instance
		{
			using G_RENDERER
			context.allocator = temp_arena_allocator
			defer mem.free_all(temp_arena_allocator)

			// Specify a list of required extensions and layers

			context.allocator = context.temp_allocator

			required_extensions := make([dynamic]cstring)
			required_layers := make([dynamic]cstring)

			// Add SDL extensions
			{
				extension_count: c.uint
				sdl.Vulkan_GetInstanceExtensions(window, &extension_count, nil)
				resize(&required_extensions, int(extension_count))
				sdl.Vulkan_GetInstanceExtensions(
					window,
					&extension_count,
					raw_data(required_extensions),
				)
			}

			// Add a couple of debug extensions and layers
			when ODIN_DEBUG {
				append(
					&required_extensions,
					vk.EXT_DEBUG_REPORT_EXTENSION_NAME,
					vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
				)
				append(&required_layers, "VK_LAYER_KHRONOS_validation")
			}

			// Check the required extensions and layers are supported
			supported_extensions := make([dynamic]vk.ExtensionProperties)
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

			supported_layers := make([dynamic]vk.LayerProperties)
			{
				layer_count: u32
				vk.EnumerateInstanceLayerProperties(&layer_count, nil)
				resize(&supported_layers, int(layer_count))
				vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(supported_layers))
			}

			for required in required_extensions {
				contains := false
				for supported in &supported_extensions {
					name := transmute(cstring)&supported.extensionName
					if name == required {
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
				for supported in &supported_layers {
					name := transmute(cstring)&supported.layerName
					if name == required {
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
				pApplicationName   = "near-renderer",
				applicationVersion = vk.MAKE_VERSION(0, 0, 1),
				pEngineName        = "near",
				engineVersion      = vk.MAKE_VERSION(0, 0, 1),
				apiVersion         = vk.API_VERSION_1_3,
			}

			instance_info := vk.InstanceCreateInfo {
				sType                   = .INSTANCE_CREATE_INFO,
				enabledExtensionCount   = u32(len(required_extensions)),
				ppEnabledExtensionNames = raw_data(required_extensions),
				enabledLayerCount       = u32(len(required_layers)),
				ppEnabledLayerNames     = raw_data(required_layers),
				pApplicationInfo        = &app_info,
			}

			if vk.CreateInstance(&instance_info, nil, &instance) != .SUCCESS {
				log.error("Failed to create Vulkan instance")
				return false
			}
		}

		// Load the rest of the functions with our instance
		vk.load_proc_addresses(G_RENDERER.instance)

		// Create a single surface for now
		if !sdl.Vulkan_CreateSurface(
			   G_RENDERER.window,
			   G_RENDERER.instance,
			   &G_RENDERER.surface,
		   ) {
			log.error("SDL couldn't create vulkan surface")
			return false
		}

		// Create physical device
		{
			using G_RENDERER
			context.allocator = temp_arena_allocator
			defer mem.free_all(temp_arena_allocator)

			physical_device_count: u32
			vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil)
			if physical_device_count == 0 {
				log.error("No physical device with Vulkan support detected")
				return false
			}

			physical_devices := make([]vk.PhysicalDevice, physical_device_count)

			vk.EnumeratePhysicalDevices(
				instance,
				&physical_device_count,
				raw_data(physical_devices),
			)

			// Find a suitable device
			for pd in &physical_devices {

				// Check extension compatibility
				extension_count: u32
				vk.EnumerateDeviceExtensionProperties(pd, nil, &extension_count, nil)

				extensions := make([]vk.ExtensionProperties, extension_count)
				vk.EnumerateDeviceExtensionProperties(pd, nil, &extension_count, raw_data(extensions))

				requied_extensions := true
				for re in &device_extensions {
					contains := false
					for e in &extensions {
						name := transmute(cstring)&e.extensionName
						if re == name {
							contains = true
							break
						}
					}
					if !contains {
						requied_extensions = false
						break
					}
				}
				if !requied_extensions {
					continue
				}

				// device capabilities
				capabilities: vk.SurfaceCapabilitiesKHR
				vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(pd, surface, &capabilities)

				// supported formats
				format_count: u32
				vk.GetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &format_count, nil)
				if format_count == 0 {
					continue
				}

				formats := make([]vk.SurfaceFormatKHR, int(format_count))
				vk.GetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &format_count, raw_data(formats))

				// supported present modes
				present_mode_count: u32
				vk.GetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &present_mode_count, nil)
				if present_mode_count == 0 {
					continue
				}

				present_modes := make([]vk.PresentModeKHR, int(present_mode_count))
				vk.GetPhysicalDeviceSurfacePresentModesKHR(
					pd,
					surface,
					&present_mode_count,
					raw_data(present_modes),
				)

				// check the device queue families
				queue_family_count: u32
				vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, nil)

				queue_families := make([]vk.QueueFamilyProperties, int(queue_family_count))
				vk.GetPhysicalDeviceQueueFamilyProperties(
					pd,
					&queue_family_count,
					raw_data(queue_families),
				)

				graphics_index := -1
				present_index := -1
				compute_index := -1
				for qf, i in &queue_families {
					if graphics_index == -1 && .GRAPHICS in qf.queueFlags {
						graphics_index = i
					} else if compute_index == -1 && .COMPUTE in qf.queueFlags {
						compute_index = i
					}

					present_support: b32
					vk.GetPhysicalDeviceSurfaceSupportKHR(pd, u32(i), surface, &present_support)
					if present_index == -1 && present_support {
						present_index = i
					}

					if graphics_index != -1 && present_index != -1 && compute_index != -1 {
						break
					}
				}

				device_props: vk.PhysicalDeviceProperties
				vk.GetPhysicalDeviceProperties(pd, &device_props)

				if graphics_index != -1 && present_index != -1 && device_props.deviceType != .CPU {

					if compute_index != -1 {
						supports_compute = true
						queue_family_compute_index = u32(compute_index)
					}

					log.infof("Picked device: %s\n ", device_props.deviceName)

					physical_device = pd
					device_capabilities = capabilities
					device_formats = slice.clone(formats)
					device_present_modes = slice.clone(present_modes)
					queue_family_graphics_index = u32(graphics_index)
					queue_family_present_index = u32(present_index)
					break
				}
			}

			if physical_device == nil {
				log.error("Suitable device not found")
				return false
			}
		}

		// Create logical device for our queues (and the queues themselves)
		{
			using G_RENDERER
			context.allocator = temp_arena_allocator
			defer mem.free_all(temp_arena_allocator)

			// Avoid creating duplicates
			queue_families: map[u32]int
			queue_families[queue_family_graphics_index] += 1
			queue_families[queue_family_present_index] += 1
			queue_families[queue_family_compute_index] += 1

			queue_priorities := make([]f32, len(queue_families))
			for qfc in 0 ..< len(queue_families) {
				queue_families[u32(qfc)] = 1.0
			}

			queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo
			for family, count in &queue_families {
				append(
					&queue_create_infos,
					vk.DeviceQueueCreateInfo{
						sType = .DEVICE_QUEUE_CREATE_INFO,
						queueFamilyIndex = u32(family),
						queueCount = u32(count),
						pQueuePriorities = raw_data(queue_priorities),
					},
				)
			}

			device_features := vk.PhysicalDeviceFeatures{}

			dynamic_rendering_frature := vk.PhysicalDeviceDynamicRenderingFeatures {
				sType            = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
				dynamicRendering = true,
			}

			device_create_info := vk.DeviceCreateInfo {
				sType                   = .DEVICE_CREATE_INFO,
				queueCreateInfoCount    = u32(len(queue_create_infos)),
				pQueueCreateInfos       = raw_data(queue_create_infos),
				enabledExtensionCount   = u32(len(device_extensions)),
				ppEnabledExtensionNames = raw_data(device_extensions),
				pEnabledFeatures        = &device_features,
				pNext                   = &dynamic_rendering_frature,
			}

			if result := vk.CreateDevice(
				   physical_device,
				   &device_create_info,
				   nil,
				   &device,
			   ); result != .SUCCESS {
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

			if supports_compute {
				vk.GetDeviceQueue(device, u32(queue_family_compute_index), 0, &compute_queue)
				if compute_queue == nil {
					log.error("Couldn't create compute queue")
					return false
				}
			}
		}

		// Load device function pointers
		vk.load_proc_addresses(G_RENDERER.device)

		// Get the swapchain working

		// also the image views for the framebuffers (what part of the framebuffer to use)
		G_RENDERER.swapchain_images = make([dynamic]vk.Image, G_RENDERER.allocator)

		// find ideal format for surface
		{
			ideal_format := false

			for format in &G_RENDERER.device_formats {
				if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
					G_RENDERER.surface_format = format
					ideal_format = true
					break
				}
			}

			if !ideal_format {
				G_RENDERER.surface_format = G_RENDERER.device_formats[0]
			}
		}

		// find ideal mode for presentation
		{
			ideal_present_mode := false
			for present_mode in &G_RENDERER.device_present_modes {
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

		// find ideal swap extent from capabilities or sdl2
		{
			using G_RENDERER
			swap_extent = device_capabilities.currentExtent
			if swap_extent.width == max(u32) {
				width, height: c.int
				sdl.Vulkan_GetDrawableSize(window, &width, &height)
				swap_extent.width = clamp(
					u32(width),
					device_capabilities.minImageExtent.width,
					device_capabilities.maxImageExtent.width,
				)
				swap_extent.height = clamp(
					u32(height),
					device_capabilities.minImageExtent.height,
					device_capabilities.maxImageExtent.height,
				)
			}

			// prefer min + 1 images on the swapchain but no more than max
			swap_images_count := device_capabilities.minImageCount + 1
			if device_capabilities.maxImageCount > 0 && swap_images_count > device_capabilities.maxImageCount {
				swap_images_count = device_capabilities.maxImageCount
			}
			resize(&swapchain_images, int(swap_images_count))
			resize(&swapchain_image_views, int(swap_images_count))
		}

		// Create the swapchain
		{
			using G_RENDERER
			create_info := vk.SwapchainCreateInfoKHR {
				sType = .SWAPCHAIN_CREATE_INFO_KHR,
				surface = surface,
				minImageCount = u32(len(swapchain_images)),
				imageFormat = surface_format.format,
				imageColorSpace = surface_format.colorSpace,
				imageExtent = swap_extent,
				imageArrayLayers = 1,
				imageUsage = {.COLOR_ATTACHMENT},
				imageSharingMode = .EXCLUSIVE,
				preTransform = device_capabilities.currentTransform,
				compositeAlpha = {.OPAQUE},
				presentMode = present_mode,
				clipped = true,
			}

			// handle different queue families
			queue_families := []u32{
				u32(queue_family_graphics_index),
				u32(queue_family_present_index),
			}
			if queue_family_graphics_index != queue_family_present_index {
				create_info.imageSharingMode = .CONCURRENT
				create_info.queueFamilyIndexCount = 2
				create_info.pQueueFamilyIndices = raw_data(queue_families)
			}

			// finally the swapchain
			if vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain) != .SUCCESS {
				log.error("Couldn't create swapchain")
				return false
			}
		}

		// Get swap images
		{
			using G_RENDERER

			swap_images_count := u32(len(swapchain_images))
			vk.GetSwapchainImagesKHR(
				device,
				swapchain,
				&swap_images_count,
				raw_data(swapchain_images),
			)

			// Create image views for each image
			for i in 0 ..< len(swapchain_image_views) {
				create_info := vk.ImageViewCreateInfo {
					sType = .IMAGE_VIEW_CREATE_INFO,
					image = swapchain_images[i],
					viewType = .D2,
					format = surface_format.format,
					components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
					subresourceRange = {
						aspectMask = {.COLOR},
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				}

				if vk.CreateImageView(device, &create_info, nil, &swapchain_image_views[i]) != .SUCCESS {
					log.error("Error creating image view")
					return false
				}
			}
		}

		// Create synchronization semaphores for presentation
		{
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
				vk.CreateSemaphore(
					device,
					&semaphore_create_info,
					nil,
					&render_finished_semaphores[i],
				)
				vk.CreateSemaphore(
					device,
					&semaphore_create_info,
					nil,
					&image_available_semaphores[i],
				)
			}
		}

		return true
	}
	//---------------------------------------------------------------------------//
	@(private)
	backend_deinit :: proc() {
		using G_RENDERER
		for i in 0 ..< num_frames_in_flight {
			vk.DestroyFence(device, frame_fences[i], nil)
			vk.DestroySemaphore(device, render_finished_semaphores[i], nil)
			vk.DestroySemaphore(device, image_available_semaphores[i], nil)
		}
		for swap_image_view in swapchain_image_views {
			vk.DestroyImageView(device, swap_image_view, nil)
		}
		if swapchain != vk.SWAPCHAINKHR_NULL {
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
backend_update :: proc(p_dt: f32) {

	// Wait until frame resources will not be used anymore
	frame_idx := G_RENDERER.frame_idx

	vk.WaitForFences(G_RENDERER.device, 1, &G_RENDERER.frame_fences[frame_idx], true, max(u64))
	vk.ResetFences(G_RENDERER.device, 1, &G_RENDERER.frame_fences[frame_idx])

	// Acquire the index of the image we'll present to
	swap_image_index: u32
	vk.AcquireNextImageKHR(
		G_RENDERER.device,
		G_RENDERER.swapchain,
		max(u64),
		G_RENDERER.image_available_semaphores[frame_idx],
		0,
		&swap_image_index,
	)

	// Submit current frame
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &G_RENDERER.image_available_semaphores[frame_idx],
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 0,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &G_RENDERER.render_finished_semaphores[frame_idx],
	}

	vk.QueueSubmit(G_RENDERER.graphics_queue, 1, &submit_info, G_RENDERER.frame_fences[frame_idx])

	// Present current frame
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &G_RENDERER.render_finished_semaphores[frame_idx],
		swapchainCount     = 1,
		pSwapchains        = &G_RENDERER.swapchain,
		pImageIndices      = &swap_image_index,
	}

	vk.QueuePresentKHR(G_RENDERER.present_queue, &present_info)
	
	// Advace frame index
	G_RENDERER.frame_idx = (G_RENDERER.frame_idx + 1) % G_RENDERER.num_frames_in_flight
}
