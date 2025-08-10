package renderer

//---------------------------------------------------------------------------//

import "core:log"

import imgui "../third_party/odin-imgui"
import imgui_sdl2 "../third_party/odin-imgui/imgui_impl_sdl2"
import imgui_vk "../third_party/odin-imgui/imgui_impl_vulkan"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	descriptor_pool: vk.DescriptorPool,
	imgui_context:   ^imgui.Context,
}

//---------------------------------------------------------------------------//

@(private)
ui_init :: proc() -> bool {

	pool_sizes := []vk.DescriptorPoolSize{
		{.SAMPLER, 1000},
		{.COMBINED_IMAGE_SAMPLER, 1000},
		{.SAMPLED_IMAGE, 1000},
		{.STORAGE_IMAGE, 1000},
		{.UNIFORM_TEXEL_BUFFER, 1000},
		{.STORAGE_TEXEL_BUFFER, 1000},
		{.UNIFORM_BUFFER, 1000},
		{.STORAGE_BUFFER, 1000},
		{.UNIFORM_BUFFER_DYNAMIC, 1000},
		{.STORAGE_BUFFER_DYNAMIC, 1000},
		{.INPUT_ATTACHMENT, 1000},
	}

	descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets = 1000,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes = raw_data(pool_sizes),
		flags = {.FREE_DESCRIPTOR_SET},
	}

	vk.CreateDescriptorPool(
		G_RENDERER.device,
		&descriptor_pool_create_info,
		nil,
		&INTERNAL.descriptor_pool,
	)

	init_info := imgui_vk.InitInfo {
		Instance = G_RENDERER.instance,
		PhysicalDevice = G_RENDERER.physical_device,
		Device = G_RENDERER.device,
		Queue = G_RENDERER.graphics_queue,
		DescriptorPool = INTERNAL.descriptor_pool,
		MinImageCount = u32(len(G_RENDERER.swapchain_images)),
		ImageCount = u32(len(G_RENDERER.swapchain_images)),
		MSAASamples = {._1},
		UseDynamicRendering = true,
		ColorAttachmentFormat = G_RENDERER.swapchain_format.format,
	}

	INTERNAL.imgui_context = imgui.CreateContext(nil)

	imgui_sdl2.InitForVulkan(G_RENDERER.window)

	imgui.StyleColorsDark(nil)
	imgui_vk.LoadFunctions(load_vk_fn)

	if imgui_vk.Init(&init_info, 0) == false {
		log.warn("Failed to init imgui")
		return false
	}

	command_buffer_one_time_submit(create_font_textures)

	return true
}

//---------------------------------------------------------------------------//

@(private = "file")
create_font_textures :: proc(p_cmd_buff: vk.CommandBuffer) {
	imgui_vk.CreateFontsTexture(p_cmd_buff)
}

//---------------------------------------------------------------------------//

@(private = "file")
load_vk_fn :: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
	return vk.GetInstanceProcAddr(G_RENDERER.instance, function_name)
}

//---------------------------------------------------------------------------//

@(private)
ui_begin_frame :: proc() {
	imgui_sdl2.NewFrame()
	imgui_vk.NewFrame()
	imgui.NewFrame()
	imgui.SetCurrentContext(INTERNAL.imgui_context)
	imgui.Begin("Renderer", nil, {})
}

//---------------------------------------------------------------------------//

@(private)
ui_submit :: proc() {

	imgui.End()

	cmd_buff_ref := get_frame_cmd_buffer_ref()
	backend_cmd_buffer := &g_resources.backend_cmd_buffers[command_buffer_get_idx(cmd_buff_ref)]

	swapchain_rendering_info := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		imageView   = G_RENDERER.swapchain_image_views[G_RENDERER.swap_img_idx],
		loadOp      = .DONT_CARE,
		storeOp     = .STORE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		colorAttachmentCount = 1,
		pColorAttachments = &swapchain_rendering_info,
		layerCount = 1,
		renderArea = {extent = {G_RENDERER.swap_extent.width, G_RENDERER.swap_extent.height}},
	}

	vk.CmdBeginRendering(backend_cmd_buffer.vk_cmd_buff, &rendering_info)

	imgui.Render()
	imgui.EndFrame()
	imgui_vk.RenderDrawData(imgui.GetDrawData(), backend_cmd_buffer.vk_cmd_buff)

	vk.CmdEndRendering(backend_cmd_buffer.vk_cmd_buff)
}
//---------------------------------------------------------------------------//

ui_shutdown :: proc() {
	vk.DestroyDescriptorPool(G_RENDERER.device, INTERNAL.descriptor_pool, nil)
	imgui_vk.Shutdown()
	imgui_sdl2.Shutdown()
	imgui.DestroyContext(INTERNAL.imgui_context)
}

//---------------------------------------------------------------------------//

ui_process_event :: proc(p_sdl_event: ^sdl.Event) {
	imgui_sdl2.ProcessEvent(p_sdl_event)
}

//---------------------------------------------------------------------------//
