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
	ubo_refs:                 []BufferRef,
	vertex_buffer_ref:        BufferRef,
	index_buffer_ref:         BufferRef,
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
}

Vertex :: struct {
	position: glsl.vec3,
	color:    glsl.vec3,
	uv:       glsl.vec2,
}

vertex_binding_description := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

vertex_attributes_descriptions := []vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, position)),
	},
	{
		binding = 1,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
	{
		binding = 2,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = u32(offset_of(Vertex, uv)),
	},
}

g_vertices: []Vertex
g_indices: []u32

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

			render_pass_desc := RenderPassDesc {
				name = common.create_name("Vulkan Tutorial Pass"),
				resolution = .Full,
				layout = {
					render_target_blend_types = {.Default},
					depth_format = get_image(depth_buffer_ref).desc.format,
				},
			}

			render_pass_desc.layout.render_target_formats = make(
				[]ImageFormat,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			render_pass_desc.layout.render_target_formats[0] = swap_image_format
			render_pass_ref = create_render_pass(render_pass_desc)
		}

		// Create pipeline
		{
			render_pass := get_render_pass(render_pass_ref)

			vertex_shader_ref := find_shader_by_name(common.create_name("base.vert"))
			fragment_shader_ref := find_shader_by_name(common.create_name("base.frag"))
			pipeline_desc := PipelineDesc {
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
		}

		vt_create_uniform_buffers()
		vt_load_model()

		return true
	}
}

vt_pre_render :: proc() {
	vt_create_vertex_buffer()
	vt_create_index_buffer()
	vt_create_texture_image()
	vt_create_texture_image_view()
	vt_create_texture_sampler()
	vt_write_descriptor_sets()
}


deinit_vt :: proc() {
	using G_VT
	using G_RENDERER
	vk.DestroySampler(device, texture_sampler, nil)
	vk.DestroyImageView(device, texture_image_view, nil)
	destroy_image(texture_image_ref)
	for ubo_ref in ubo_refs {
		destroy_buffer(ubo_ref)
	}
	destroy_buffer(vertex_buffer_ref)
	destroy_buffer(index_buffer_ref)
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
		render_pass := get_render_pass(render_pass_ref)

		{
			// @TODO bind pipeline 
			pipeline := get_pipeline(render_pass.pipeline)

			vk.CmdBindDescriptorSets(
				p_cmd_buff.vk_cmd_buff,
				.GRAPHICS,
				get_pipeline_layout(pipeline.pipeline_layout).vk_pipeline_layout,
				0,
				1,
				&descriptor_sets[p_frame_idx],
				0,
				nil,
			)	
		}

		offset := vk.DeviceSize{}

		vertex_buffer := get_buffer(vertex_buffer_ref)
		index_buffer := get_buffer(index_buffer_ref)
		vk.CmdBindVertexBuffers(p_cmd_buff.vk_cmd_buff, 0, 1, &vertex_buffer.vk_buffer, &offset)
		vk.CmdBindIndexBuffer(p_cmd_buff.vk_cmd_buff, index_buffer.vk_buffer, offset, .UINT32)
		vk.CmdDrawIndexed(p_cmd_buff.vk_cmd_buff, u32(len(g_indices)), 1, 0, 0, 0)
		// vk.CmdDraw(cmd, u32(len(g_vertices)), 1, 0, 0)
	}
	end_render_pass(render_pass_ref, p_cmd_buff_ref)
}

vt_create_vertex_buffer :: proc() {
	using G_RENDERER
	using G_VT

	vertex_buffer_ref = allocate_buffer_ref(common.create_name("VertexBuffer"))
	vertex_buffer := get_buffer(vertex_buffer_ref)

	vertex_buffer.desc.size = u32(len(g_vertices) * size_of(MeshVertexLayout))
	vertex_buffer.desc.usage = {.VertexBuffer, .TransferDst}
	vertex_buffer.desc.flags = {.Dedicated}
	create_buffer(vertex_buffer_ref)

	upload_request := BufferUploadRequest {
		dst_buff          = vertex_buffer_ref,
		dst_buff_offset   = 0,
		dst_queue_usage   = .Graphics,
		first_usage_stage = .VertexInput,
		size              = u32(len(g_vertices) * size_of(Vertex)),
	}

	response := request_buffer_upload(upload_request)
	assert(response.ptr != nil)

	mem.copy(response.ptr, raw_data(g_vertices), len(g_vertices) * size_of(Vertex))
}

vt_create_index_buffer :: proc() {
	using G_RENDERER
	using G_VT

	index_buffer_ref = allocate_buffer_ref(common.create_name("IndexBuffer"))
	index_buffer := get_buffer(index_buffer_ref)
	index_buffer.desc.size = u32(len(g_indices) * size_of(g_indices[0]))
	index_buffer.desc.usage = {.IndexBuffer, .TransferDst}
	index_buffer.desc.flags = {.Dedicated}
	create_buffer(index_buffer_ref)

	upload_request := BufferUploadRequest {
		dst_buff          = index_buffer_ref,
		dst_buff_offset   = 0,
		dst_queue_usage   = .Graphics,
		first_usage_stage = .VertexInput,
		size              = index_buffer.desc.size,
	}
	response := request_buffer_upload(upload_request)
	assert(response.ptr != nil)
	mem.copy(response.ptr, raw_data(g_indices), int(index_buffer.desc.size))
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

vt_create_uniform_buffers :: proc() {
	using G_RENDERER
	using G_VT

	ubo_refs = make([]BufferRef, num_frames_in_flight, G_RENDERER_ALLOCATORS.main_allocator)

	for i in 0 ..< num_frames_in_flight {
		ubo_refs[i] = allocate_buffer_ref(common.create_name("UBO"))
		ubo := get_buffer(ubo_refs[i])

		ubo.desc.flags = {.HostWrite, .Mapped}
		ubo.desc.size = size_of(UniformBufferObject)
		ubo.desc.usage = {.UniformBuffer}

		create_buffer(ubo_refs[i])
	}

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

	uniform_buffer := get_buffer(ubo_refs[get_frame_idx()])
	mem.copy(uniform_buffer.mapped_ptr, &ubo, size_of(UniformBufferObject))
}

vt_write_descriptor_sets :: proc() {
	using G_RENDERER
	using G_VT

	ubo_info := vk.DescriptorBufferInfo {
		range = size_of(UniformBufferObject),
	}
	ubo_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = 0,
		dstSet          = 0,
		descriptorCount = 1,
		descriptorType  = .UNIFORM_BUFFER,
		pBufferInfo     = &ubo_info,
	}

	image_info := vk.DescriptorImageInfo {
		sampler     = texture_sampler,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = texture_image_view,
	}

	image_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = 0,
		dstBinding      = 1,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &image_info,
	}


	for i in 0 ..< num_frames_in_flight {
		uniform_buffer := get_buffer(ubo_refs[i])
		ubo_info.buffer = uniform_buffer.vk_buffer
		ubo_write.dstSet = descriptor_sets[i]
		image_write.dstSet = descriptor_sets[i]
		descriptor_writes := []vk.WriteDescriptorSet{ubo_write, image_write}

		vk.UpdateDescriptorSets(
			device,
			u32(len(descriptor_writes)),
			raw_data(descriptor_writes),
			0,
			nil,
		)
	}
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
	} else if p_old_layout == .TRANSFER_DST_OPTIMAL && p_new_layout == .SHADER_READ_ONLY_OPTIMAL {
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
	vk.CmdPipelineBarrier(cmd_buff, src_stage, dst_stage, nil, 0, nil, 0, nil, 1, &barrier)
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
	vk.CmdCopyBufferToImage(cmd_buff, p_buffer, p_image, .TRANSFER_DST_OPTIMAL, 1, &region)
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

	if vk.CreateSampler(device, &sampler_create_info, nil, &texture_sampler) != .SUCCESS {
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

	g_vertices = make([]Vertex, num_vertices)
	g_indices = make([]u32, num_indices)

	import_ctx: ImportContext

	vt_assimp_load_node(scene, scene.mRootNode, &import_ctx)
}

ImportContext :: struct {
	curr_vtx: u32,
	curr_idx: u32,
}

vt_assimp_load_node :: proc(
	p_scene: ^assimp.Scene,
	p_node: ^assimp.Node,
	p_import_ctx: ^ImportContext,
) {
	for i in 0 ..< p_node.mNumMeshes {
		mesh := p_scene.mMeshes[i]
		for j in 0 ..< mesh.mNumVertices {
			vertex := Vertex {
				position = {mesh.mVertices[j].x, mesh.mVertices[j].y, mesh.mVertices[j].z},
				color = {0, 0, 0},
				uv = {mesh.mTextureCoords[0][j].x, mesh.mTextureCoords[0][j].y},
			}
			g_vertices[p_import_ctx.curr_vtx] = vertex
			p_import_ctx.curr_vtx += 1
		}

		for j in 0 ..< mesh.mNumFaces {
			for k in 0 ..< mesh.mFaces[j].mNumIndices {
				g_indices[p_import_ctx.curr_idx] = mesh.mFaces[j].mIndices[k]
				p_import_ctx.curr_idx += 1
			}
		}
	}

	for i in 0 ..< p_node.mNumChildren {
		vt_assimp_load_node(p_scene, p_node.mChildren[i], p_import_ctx)
	}
}
