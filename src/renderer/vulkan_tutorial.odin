package renderer

import "core:math/linalg/glsl"
import "core:mem"
import "core:time"

import "../common"

G_VT: struct {
	ubo_ref:                 BufferRef,
	start_time:              time.Time,
	depth_buffer_ref:        ImageRef,
	render_pass_ref:         RenderPassRef,
	pipeline_ref:            PipelineRef,
	depth_buffer_attachment: DepthAttachment,
	render_target_bindings:  []RenderTargetBinding,
	draw_stream:             DrawStream,
	viking_room_mesh_ref:    MeshRef,
}

@(private = "file")
UniformBufferObject :: struct {
	model: glsl.mat4x4,
	view:  glsl.mat4x4,
	proj:  glsl.mat4x4,
}

init_vt :: proc() -> bool {

	material_instance_ref := allocate_material_instance_ref(common.create_name("FlightHelmetMat"))
	material_instance := &g_resources.material_instances[get_material_instance_idx(material_instance_ref)]
	material_instance.desc.material_type_ref = find_material_type("Default")
	create_material_instance(material_instance_ref)

	mesh_instance_ref := allocate_mesh_instance_ref(common.create_name("FlightHelmet"))
	create_mesh_instance(mesh_instance_ref)

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
			swap_image_format :=
				g_resources.images[get_image_idx(G_RENDERER.swap_image_refs[0])].desc.format
			depth_image := &g_resources.images[get_image_idx(depth_buffer_ref)]

			render_pass_ref = allocate_render_pass_ref(
				common.create_name("Vulkan tutorial Render Pass"),
			)
			render_pass := &g_resources.render_passes[get_render_pass_idx(render_pass_ref)]
			render_pass.desc = RenderPassDesc {
				resolution = .Full,
				layout = {
					render_target_blend_types = {.Default},
					depth_format = depth_image.desc.format,
				},
				primitive_type = .TriangleList,
				resterizer_type = .Fill,
				multisampling_type = ._1,
				depth_stencil_type = .DepthTestWrite,
			}

			render_pass.desc.layout.render_target_formats = make(
				[]ImageFormat,
				1,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)

			render_pass.desc.layout.render_target_formats[0] = swap_image_format
			create_render_pass(render_pass_ref)
		}

		vt_create_uniform_buffer()

		draw_stream = draw_stream_create(G_RENDERER_ALLOCATORS.main_allocator)

		return true
	}
}

deinit_vt :: proc() {
	using G_VT
	using G_RENDERER
	destroy_buffer(ubo_ref)
}

vt_update :: proc(p_frame_idx: u32, p_image_idx: u32, p_cmd_buff_ref: CommandBufferRef) {
	using G_VT

	vt_update_uniform_buffer()

	return
	// G_VT.viking_room_mesh_ref = find_mesh("FlightHelmet")

	// render_target_bindings[0].target = &G_RENDERER.swap_image_render_targets[p_image_idx]

	// begin_info := RenderPassBeginInfo {
	// 	depth_attachment        = &depth_buffer_attachment,
	// 	render_targets_bindings = render_target_bindings,
	// }

	// begin_render_pass(render_pass_ref, p_cmd_buff_ref, &begin_info)
	// {
	// 	// Setup the draw stream
	// 	draw_stream_reset(&draw_stream)

	// 	// Draw mesh
	// 	{
	// 		mesh := &g_resources.meshes[get_mesh_idx(G_VT.viking_room_mesh_ref)]

	// 		for submesh in mesh.desc.sub_meshes {
	// 			material_instance := &g_resources.material_instances[get_material_instance_idx(submesh.material_instance_ref)]
	// 			ubo_offset := []u32{0, size_of(UniformBufferObject) * get_frame_idx()}

	// 			draw_stream_add_draw(
	// 				&draw_stream,
	// 				p_pipeline_ref = G_VT.pipeline_ref,
	// 				p_vertex_buffers = {
	// 					OffsetBuffer{
	// 						buffer_ref = mesh_get_global_vertex_buffer_ref(),
	// 						offset = mesh.vertex_buffer_allocation.offset,
	// 					},
	// 				},
	// 				p_index_buffer = {
	// 					buffer_ref = mesh_get_global_index_buffer_ref(),
	// 					offset = mesh.index_buffer_allocation.offset +
	// 					size_of(u32) * submesh.data_offset,
	// 				},
	// 				p_bind_groups = {
	// 					{bind_group_ref = InvalidBindGroupRef},
	// 					{
	// 						bind_group_ref = G_RENDERER.global_bind_group_ref,
	// 						dynamic_offsets = ubo_offset,
	// 					},
	// 					{bind_group_ref = G_RENDERER.bindless_textures_array_bind_group_ref},
	// 				},
	// 				p_push_constants = []rawptr{
	// 					&material_instance.material_properties_buffer_entry_idx,
	// 				},
	// 				p_draw_count = submesh.data_count,
	// 				p_instance_count = 1,
	// 			)
	// 		}
	// 	}

	// 	// Dispatch the stream
	// 	//draw_stream_dispatch(p_cmd_buff_ref, &G_VT.draw_stream)

	// }
	// end_render_pass(render_pass_ref, p_cmd_buff_ref)
}

vt_create_uniform_buffer :: proc() {
	using G_RENDERER
	using G_VT

	ubo_ref = allocate_buffer_ref(common.create_name("UBO"))
	ubo := &g_resources.buffers[get_buffer_idx(ubo_ref)]

	ubo.desc.flags = {.HostWrite, .Mapped}
	ubo.desc.size = size_of(UniformBufferObject) * num_frames_in_flight
	ubo.desc.usage = {.DynamicUniformBuffer}

	create_buffer(ubo_ref)

	// Write this uniform buffer to the global bind group
	material_properties_buffer_ref := material_type_get_properties_buffer()
	material_properties_buffer := &g_resources.buffers[get_buffer_idx(material_properties_buffer_ref)]

	bind_group_update(
		G_RENDERER.global_bind_group_ref,
		BindGroupUpdate{
			buffers = {
				{
					buffer_ref = material_properties_buffer_ref,
					size = material_properties_buffer.desc.size,
				},
				{buffer_ref = InvalidBufferRef, size = 0},
				{buffer_ref = ubo_ref, size = size_of(UniformBufferObject)},
			},
		},
	)
}

// @TODO use p_dt
vt_update_uniform_buffer :: proc() {
	using G_RENDERER
	using G_VT

	current_time := time.now()
	dt := f32(time.duration_seconds(time.diff(start_time, current_time)))

	ubo := UniformBufferObject {
		model = glsl.identity(glsl.mat4) * glsl.mat4Rotate({0, 1, 0}, glsl.radians_f32(90.0) * dt),
		view  = glsl.mat4LookAt({0, 1.0, 1.5}, {0, 0.3, 0}, {0, 1, 0}),
		proj  = glsl.mat4Perspective(
			glsl.radians_f32(45.0),
			f32(swap_extent.width) / f32(swap_extent.height),
			0.1,
			10.0,
		),
	}

	uniform_buffer := &g_resources.buffers[get_buffer_idx(ubo_ref)]
	mem.copy(
		mem.ptr_offset(uniform_buffer.mapped_ptr, size_of(UniformBufferObject) * get_frame_idx()),
		&ubo,
		size_of(UniformBufferObject),
	)
}
