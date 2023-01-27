package renderer

import "core:math/linalg/glsl"
import "core:mem"
import "core:log"
import "core:time"
import "core:c"

import vk "vendor:vulkan"
import stb_image "vendor:stb/image"

import vma "../third_party/vma"
import assimp "../third_party/assimp"
import "../common"

G_VT: struct {
	ubo_ref:                  BufferRef,
	start_time:               time.Time,
	texture_image_ref:        ImageRef,
	texture_image_allocation: vma.Allocation,
	texture_image_view:       vk.ImageView,
	texture_sampler:          vk.Sampler,
	depth_buffer_ref:         ImageRef,
	render_pass_ref:          RenderPassRef,
	pipeline_ref:             PipelineRef,
	depth_buffer_attachment:  DepthAttachment,
	render_target_bindings:   []RenderTargetBinding,
	ubo_bind_group_ref:       BindGroupRef,
	texture_bind_group_ref:   BindGroupRef,
	draw_stream:              DrawStream,
	bind_group_bindings:      []BindGroupBinding,
	viking_room_mesh_ref:     MeshRef,
}

MODEL_PATH :: "app_data/renderer/assets/models/viking_room.obj"
MODEL_TEXTURE_PATH :: "app_data/renderer/assets/models/viking_room.png"

UniformBufferObject :: struct {
	model: glsl.mat4x4,
	view:  glsl.mat4x4,
	proj:  glsl.mat4x4,
}

init_vt :: proc() -> bool {

	{
		using G_RENDERER
		using G_VT

		start_time = time.now()

		// Create depth buffer
		{
			depth_buffer_desc := ImageDesc {
				type = .OneDimensional,
				format = .Depth32SFloat,
				mip_count = 1,
				data_per_mip = nil,
				sample_count_flags = {._1},
				dimensions = {swap_extent.width, swap_extent.height, 1},
			}


			depth_buffer_ref = create_depth_buffer(
				common.create_name("DepthBuffer"),
				depth_buffer_desc,
			)

			depth_buffer_attachment = DepthAttachment {
				image = depth_buffer_ref,
			}
		}

		render_target_bindings = make(
			[]RenderTargetBinding,
			1,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		// Create render pass
		{
			swap_image_format := get_image(G_RENDERER.swap_image_refs[0]).desc.format

			render_pass_ref = allocate_render_pass_ref(
				common.create_name("Vulkan tutorial Render Pass"),
			)
			render_pas := get_render_pass(render_pass_ref)
			render_pas.desc = RenderPassDesc {
				resolution = .Full,
				layout = {
					render_target_blend_types = {.Default},
					depth_format = get_image(depth_buffer_ref).desc.format,
				},
			}

			render_pas.desc.layout.render_target_formats = make(
				[]ImageFormat,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			render_pas.desc.layout.render_target_formats[0] = swap_image_format
			create_render_pass(render_pass_ref)
		}

		// Create pipeline
		{
			render_pass := get_render_pass(render_pass_ref)

			vertex_shader_ref := find_shader_by_name(common.create_name("base.vert"))
			fragment_shader_ref := find_shader_by_name(common.create_name("base.frag"))
			pipeline_ref = allocate_pipeline_ref(
				common.create_name("Vulkan Tutorial Pipeline"),
			)
			get_pipeline(pipeline_ref).desc = {
				name               = common.create_name("Vulkan Tutorial Pipe"),
				vert_shader        = vertex_shader_ref,
				frag_shader        = fragment_shader_ref,
				vertex_layout      = .Mesh,
				primitive_type     = .TriangleList,
				resterizer_type    = .Fill,
				multisampling_type = ._1,
				depth_stencil_type = .DepthTestWrite,
				render_pass_layout = render_pass.desc.layout,
			}
			create_graphics_pipeline(pipeline_ref)
		}

		vt_create_uniform_buffer()
		vt_load_model()
		return true
	}
}

vt_pre_render :: proc() {

	using G_RENDERER
	using G_VT

	vt_create_texture_image()
	vt_create_texture_image_view()
	vt_create_texture_sampler()
	vt_create_bind_groups()

	// Setup the draw stream
	{
		viking_room_mesh := get_mesh(G_VT.viking_room_mesh_ref)

		draw_stream_init(G_RENDERER_ALLOCATORS.main_allocator, &G_VT.draw_stream)
		draw_stream_change_pipeline(&G_VT.draw_stream, G_VT.pipeline_ref)
		bind_group_bindings = draw_stream_change_bindings(&G_VT.draw_stream, 2)
		bind_group_bindings[0].bind_group_ref = ubo_bind_group_ref
		bind_group_bindings[0].dynamic_offsets = make([]u32, 1, draw_stream.allocator)
		bind_group_bindings[1].bind_group_ref = texture_bind_group_ref

		cube_draw := draw_stream_add_indexed_draw(&G_VT.draw_stream)
		cube_draw.index_buffer_ref = MESH_INTERNAL.index_buffer_ref
		cube_draw.instance_count = 1
		cube_draw.index_count = u32(len(viking_room_mesh.desc.indices))
		cube_draw.vertex_buffer_ref = MESH_INTERNAL.vertex_buffer_ref
		cube_draw.index_type = .UInt16
		draw_stream_reset(&G_VT.draw_stream)

	}
}

vt_create_bind_groups :: proc() {
	using G_RENDERER
	using G_VT

	// Create the bind groups
	{
		refs := []BindGroupRef{InvalidBindGroupRef, InvalidBindGroupRef}
		create_bind_groups_for_pipeline(pipeline_ref, refs)

		ubo_bind_group_ref = refs[0]
		texture_bind_group_ref = refs[1]
	}

	// Update the bind groups
	{
		ubo_bind_group_update := BindGroupUpdate {
			bind_group_ref = ubo_bind_group_ref,
			buffer_updates = {
				{
					slot = 0,
					buffer = ubo_ref,
					offset = 0,
					size = size_of(UniformBufferObject) * num_frames_in_flight,
				},
			},
		}

		texture_bind_group_update := BindGroupUpdate {
			bind_group_ref = texture_bind_group_ref,
			image_updates = {{image_ref = texture_image_ref, mip = 0, slot = 1}},
		}

		update_bind_groups({ubo_bind_group_update, texture_bind_group_update})
	}
}


deinit_vt :: proc() {
	using G_VT
	using G_RENDERER
	vk.DestroySampler(device, texture_sampler, nil)
	vk.DestroyImageView(device, texture_image_view, nil)
	destroy_image(texture_image_ref)
	destroy_buffer(ubo_ref)
	destroy_bind_groups({texture_bind_group_ref, ubo_bind_group_ref})
}

vt_update :: proc(
	p_frame_idx: u32,
	p_image_idx: u32,
	p_cmd_buff_ref: CommandBufferRef,
	p_cmd_buff: ^CommandBufferResource,
) {
	using G_VT

	vt_update_uniform_buffer()

	render_target_bindings[0].target = &G_RENDERER.swap_image_render_targets[p_image_idx]

	begin_info := RenderPassBeginInfo {
		depth_attachment        = &depth_buffer_attachment,
		render_targets_bindings = render_target_bindings,
	}

	begin_render_pass(render_pass_ref, p_cmd_buff_ref, &begin_info)
	{
		bind_group_bindings[0].dynamic_offsets = {
			size_of(UniformBufferObject) * get_frame_idx(),
		}

		draw_stream_reset(&draw_stream)
		draw_stream_submit(p_cmd_buff_ref, &draw_stream)
	}
	end_render_pass(render_pass_ref, p_cmd_buff_ref)
}

vt_create_buffer :: proc(
	p_size: vk.DeviceSize,
	p_usage: vk.BufferUsageFlags,
	p_alloc_usage: vma.MemoryUsage,
	p_alloc_flags: vma.AllocationCreateFlags,
) -> (
	vk.Buffer,
	vma.Allocation,
) {
	using G_RENDERER
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = p_size,
		usage       = p_usage,
		sharingMode = .EXCLUSIVE,
	}
	alloc_info := vma.AllocationCreateInfo {
		usage = p_alloc_usage,
		flags = p_alloc_flags,
	}

	buffer: vk.Buffer
	alloc: vma.Allocation
	alloc_infos: vma.AllocationInfo
	res := vma.create_buffer(
		vma_allocator,
		&buffer_info,
		&alloc_info,
		&buffer,
		&alloc,
		&alloc_infos,
	)
	if res != .SUCCESS {
		log.warn("Failed to create buffer")
		return 0, nil
	}
	return buffer, alloc
}

vt_copy_buffer :: proc(
	p_src_buffer: vk.Buffer,
	p_dst_buffer: vk.Buffer,
	p_size: vk.DeviceSize,
) {
	using G_VT
	using G_RENDERER
	copy_cmd_buff := vt_begin_single_time_command_buffer()
	copy_region := vk.BufferCopy {
		size = p_size,
	}
	vk.CmdCopyBuffer(copy_cmd_buff, p_src_buffer, p_dst_buffer, 1, &copy_region)
	vt_end_single_time_command_buffer(copy_cmd_buff)
}

vt_create_uniform_buffer :: proc() {
	using G_RENDERER
	using G_VT

	ubo_ref = allocate_buffer_ref(common.create_name("UBO"))
	ubo := get_buffer(ubo_ref)

	ubo.desc.flags = {.HostWrite, .Mapped}
	ubo.desc.size = size_of(UniformBufferObject) * num_frames_in_flight
	ubo.desc.usage = {.DynamicUniformBuffer}

	create_buffer(ubo_ref)
}

// @TODO use p_dt
vt_update_uniform_buffer :: proc() {
	using G_RENDERER
	using G_VT

	current_time := time.now()
	dt := f32(time.duration_seconds(time.diff(start_time, current_time)))


	ubo := UniformBufferObject {
		model = glsl.identity(
			glsl.mat4,
		) * glsl.mat4Rotate({0, 0, 1}, glsl.radians_f32(90.0) * dt),
		view  = glsl.mat4LookAt({0, 3.0, 1.5}, {0, 0, 0}, {0, 1, 0}),
		proj  = glsl.mat4Perspective(
			glsl.radians_f32(45.0),
			f32(swap_extent.width) / f32(swap_extent.height),
			0.1,
			10.0,
		),
	}

	uniform_buffer := get_buffer(ubo_ref)
	mem.copy(
		mem.ptr_offset(
			uniform_buffer.mapped_ptr,
			size_of(UniformBufferObject) * get_frame_idx(),
		),
		&ubo,
		size_of(UniformBufferObject),
	)
}

vt_create_texture_image :: proc() {
	using G_RENDERER
	using G_VT

	image_width, image_height, channels: c.int
	pixels := stb_image.load(
		"app_data/renderer/assets/textures/viking_room.png",
		&image_width,
		&image_height,
		&channels,
		4,
	)

	if pixels == nil {
		log.debug("Failed to load image")
	}

	texture_image_ref = allocate_image_ref(common.create_name("VikingRoom"))
	texture_image := get_image(texture_image_ref)
	texture_image.desc.type = .TwoDimensional
	texture_image.desc.format = .RGBA8_SRGB
	texture_image.desc.mip_count = 1
	texture_image.desc.data_per_mip = {pixels[0:image_width * image_height * 4]}
	texture_image.desc.dimensions = {u32(image_width), u32(image_height), 1}
	texture_image.desc.sample_count_flags = {._1}

	create_texture_image(texture_image_ref)

	stb_image.image_free(pixels)
}


vt_begin_single_time_command_buffer :: proc() -> vk.CommandBuffer {
	using G_VT
	using G_RENDERER

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = INTERNAL.graphics_command_pools[0],
		commandBufferCount = 1,
	}
	cmd_buff: vk.CommandBuffer
	vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buff)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(cmd_buff, &begin_info)
	return cmd_buff
}

vt_end_single_time_command_buffer :: proc(cmd_buff: vk.CommandBuffer) {
	using G_VT
	using G_RENDERER

	vk.EndCommandBuffer(cmd_buff)

	command_buffer := cmd_buff
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}
	vk.QueueSubmit(graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(graphics_queue)
}

vt_transition_image_layout :: proc(
	p_image: vk.Image,
	p_old_layout: vk.ImageLayout,
	p_new_layout: vk.ImageLayout,
) {

	cmd_buff := vt_begin_single_time_command_buffer()
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = p_old_layout,
		newLayout = p_new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = p_image,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	src_stage: vk.PipelineStageFlags
	dst_stage: vk.PipelineStageFlags
	if p_old_layout == .UNDEFINED && p_new_layout == .TRANSFER_DST_OPTIMAL {
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.TRANSFER}
	} else if
	   p_old_layout == .TRANSFER_DST_OPTIMAL &&
	   p_new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		src_stage = {.TRANSFER}
		dst_stage = {.FRAGMENT_SHADER}
	} else if p_old_layout == .UNDEFINED && p_new_layout == .DEPTH_ATTACHMENT_OPTIMAL {
		barrier.dstAccessMask = {
			.DEPTH_STENCIL_ATTACHMENT_READ,
			.DEPTH_STENCIL_ATTACHMENT_WRITE,
		}

		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.EARLY_FRAGMENT_TESTS}

	}
	vk.CmdPipelineBarrier(
		cmd_buff,
		src_stage,
		dst_stage,
		nil,
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
	vt_end_single_time_command_buffer(cmd_buff)

}

vt_copy_buffer_to_image :: proc(
	p_buffer: vk.Buffer,
	p_image: vk.Image,
	p_width: u32,
	p_height: u32,
) {
	cmd_buff := vt_begin_single_time_command_buffer()
	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {width = p_width, height = p_height, depth = 1},
	}
	vk.CmdCopyBufferToImage(
		cmd_buff,
		p_buffer,
		p_image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)
	vt_end_single_time_command_buffer(cmd_buff)
}

vt_create_texture_image_view :: proc() {
	texture_image := get_image(G_VT.texture_image_ref)
	G_VT.texture_image_view = vt_create_image_view(
		texture_image.vk_image,
		.R8G8B8A8_SRGB,
		{.COLOR},
	)
}

vt_create_image_view :: proc(
	p_image: vk.Image,
	p_format: vk.Format,
	p_aspect_mask: vk.ImageAspectFlags,
) -> vk.ImageView {
	using G_RENDERER
	using G_VT

	view_create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = p_image,
		viewType = .D2,
		format = p_format,
		subresourceRange = {aspectMask = p_aspect_mask, levelCount = 1, layerCount = 1},
	}

	image_view: vk.ImageView
	if vk.CreateImageView(device, &view_create_info, nil, &image_view) != .SUCCESS {
		log.warn("Failed to create image view")
	}
	return image_view
}

vt_create_texture_sampler :: proc() {
	using G_RENDERER
	using G_VT

	sampler_create_info := vk.SamplerCreateInfo {
		sType            = .SAMPLER_CREATE_INFO,
		magFilter        = .LINEAR,
		minFilter        = .LINEAR,
		addressModeU     = .REPEAT,
		addressModeV     = .REPEAT,
		addressModeW     = .REPEAT,
		anisotropyEnable = true,
		maxAnisotropy    = device_properties.limits.maxSamplerAnisotropy,
		borderColor      = .INT_OPAQUE_BLACK,
		compareOp        = .ALWAYS,
		mipmapMode       = .LINEAR,
	}

	if
	   vk.CreateSampler(device, &sampler_create_info, nil, &texture_sampler) !=
	   .SUCCESS {
		log.warn("Failed to create sampler")
	}
}

vt_load_model :: proc() {

	scene := assimp.import_file(
		"app_data/renderer/assets/models/viking_room.obj",
		{.OptimizeMeshes, .Triangulate, .FlipUVs},
	)
	if scene == nil {
		log.fatalf("Failed to load he model")
	}
	defer assimp.release_import(scene)

	num_vertices: u32 = 0
	num_indices: u32 = 0
	for i in 0 ..< scene.mNumMeshes {
		num_vertices += u32(scene.mMeshes[i].mNumVertices)
		num_indices += u32(scene.mMeshes[i].mNumFaces * 3)
	}

	mesh_ref := allocate_mesh_ref(common.create_name("VikingRoom"))
	mesh := get_mesh(mesh_ref)

	mesh.desc.indices = make([]u16, int(num_indices))
	mesh.desc.position = make([]glsl.vec3, int(num_vertices))
	mesh.desc.uv = make([]glsl.vec2, int(num_vertices))
	mesh.desc.sub_meshes = make([]SubMesh, scene.mNumMeshes)
	mesh.desc.features = {.UV}
	mesh.desc.flags = {.Indexed}

	import_ctx: ImportContext
	import_ctx.mesh = mesh

	vt_assimp_load_node(scene, scene.mRootNode, &import_ctx)

	create_mesh(mesh_ref)

	G_VT.viking_room_mesh_ref = mesh_ref
}

ImportContext :: struct {
	curr_vtx:         u32,
	curr_idx:         u32,
	current_sub_mesh: u32,
	mesh:             ^MeshResource,
}

vt_assimp_load_node :: proc(
	p_scene: ^assimp.Scene,
	p_node: ^assimp.Node,
	p_import_ctx: ^ImportContext,
) {

	for i in 0 ..< p_node.mNumMeshes {
		assimp_mesh := p_scene.mMeshes[i]

		sub_mesh := &p_import_ctx.mesh.desc.sub_meshes[p_import_ctx.current_sub_mesh]
		sub_mesh.data_count = assimp_mesh.mNumVertices
		sub_mesh.data_offset = p_import_ctx.curr_vtx

		for j in 0 ..< assimp_mesh.mNumVertices {

			p_import_ctx.mesh.desc.position[p_import_ctx.curr_vtx] = {
				assimp_mesh.mVertices[j].x,
				assimp_mesh.mVertices[j].y,
				assimp_mesh.mVertices[j].z,
			}

			p_import_ctx.mesh.desc.uv[p_import_ctx.curr_vtx] = {
				assimp_mesh.mTextureCoords[0][j].x,
				assimp_mesh.mTextureCoords[0][j].y,
			}

			p_import_ctx.curr_vtx += 1
		}

		for j in 0 ..< assimp_mesh.mNumFaces {
			for k in 0 ..< assimp_mesh.mFaces[j].mNumIndices {
				p_import_ctx.mesh.desc.indices[p_import_ctx.curr_idx] = u16(
					assimp_mesh.mFaces[j].mIndices[k],
				)
				p_import_ctx.curr_idx += 1
			}
		}

		p_import_ctx.current_sub_mesh += 1
	}

	for i in 0 ..< p_node.mNumChildren {
		vt_assimp_load_node(p_scene, p_node.mChildren[i], p_import_ctx)
	}
}
