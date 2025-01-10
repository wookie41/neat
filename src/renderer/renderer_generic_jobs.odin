package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

GenericComputeJob :: struct {
	compute_command_ref:   ComputeCommandRef,
	bind_group_ref:        BindGroupRef,
	bind_group_layout_ref: BindGroupLayoutRef,
}

//---------------------------------------------------------------------------//

GenericPixelJob :: struct {
	bind_group_ref:        BindGroupRef,
	bind_group_layout_ref: BindGroupLayoutRef,
	draw_command_ref:      DrawCommandRef,
	render_pass_ref:       RenderPassRef,
}

//---------------------------------------------------------------------------//

@(private)
GenericComputeJobUniformData :: struct #packed {
	texel_size:   glsl.vec2,
	texture_size: glsl.ivec2,
}

//---------------------------------------------------------------------------//

@(private)
generic_compute_job_create :: proc(
	p_name: common.Name,
	p_shader_ref: ShaderRef,
	p_render_pass_bindings: RenderPassBindings,
	p_is_compute_render_target_pass: bool,
) -> (
	out_job: GenericComputeJob,
	out_success: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Create a bind group layout and bind group based on the input images and buffers
	bind_group_ref, bind_group_layout_ref := create_bind_group_for_bindings(
		p_name,
		p_render_pass_bindings,
		true,
		p_is_compute_render_target_pass,
		temp_arena.allocator,
	)
	if bind_group_ref == InvalidBindGroupRef {
		return {}, false
	}

	// Create the compute command 
	compute_command_ref := compute_command_allocate_ref(p_name, 4, 0)
	compute_command := &g_resources.compute_commands[compute_command_get_idx(compute_command_ref)]

	compute_command.desc.bind_group_layout_refs[0] = bind_group_layout_ref
	compute_command.desc.bind_group_layout_refs[1] = G_RENDERER.uniforms_bind_group_layout_ref
	compute_command.desc.bind_group_layout_refs[2] = G_RENDERER.globals_bind_group_layout_ref
	compute_command.desc.bind_group_layout_refs[3] = G_RENDERER.bindless_bind_group_layout_ref

	compute_command.desc.compute_shader_ref = p_shader_ref

	compute_command_create(compute_command_ref)

	compute_command_set_bind_group(compute_command_ref, 0, bind_group_ref)
	compute_command_set_bind_group(compute_command_ref, 1, G_RENDERER.uniforms_bind_group_ref)
	compute_command_set_bind_group(compute_command_ref, 2, G_RENDERER.globals_bind_group_ref)
	compute_command_set_bind_group(compute_command_ref, 3, G_RENDERER.bindless_bind_group_ref)

	return GenericComputeJob {
			compute_command_ref = compute_command_ref,
			bind_group_layout_ref = bind_group_layout_ref,
			bind_group_ref = bind_group_ref,
		},
		true
}

//---------------------------------------------------------------------------//

@(private)
generic_pixel_job_create :: proc(
	p_name: common.Name,
	p_shader_ref: ShaderRef,
	p_render_pass_bindings: RenderPassBindings,
	p_resolution: glsl.uvec2,
) -> (
	out_job: GenericPixelJob,
	out_success: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Create a render pass based on output images
	render_pass_ref := allocate_render_pass_ref(p_name, len(p_render_pass_bindings.image_outputs))
	render_pass := &g_resources.render_passes[get_render_pass_idx(render_pass_ref)]
	render_pass.desc.depth_stencil_type = .None
	render_pass.desc.primitive_type = .TriangleList
	render_pass.desc.resterizer_type = .Default
	render_pass.desc.multisampling_type = ._1
	render_pass.desc.resolution = p_resolution

	for output_image, i in p_render_pass_bindings.image_outputs {
		image := &g_resources.images[get_image_idx(output_image.image_ref)]
		render_pass.desc.layout.render_target_formats[i] = image.desc.format
		render_pass.desc.layout.render_target_blend_types[i] = .Default
	}

	create_render_pass(render_pass_ref) or_return

	// Create a bind group layout and bind group based on the input images and buffers
	bind_group_ref, bind_group_layout_ref := create_bind_group_for_bindings(
		p_name,
		p_render_pass_bindings,
		false,
		false,
		temp_arena.allocator,
	)
	if bind_group_ref == InvalidBindGroupRef {
		return {}, false
	}

	// Create the draw command 
	draw_command_ref := draw_command_allocate_ref(p_name, 4, 0)
	draw_command := &g_resources.draw_commands[draw_command_get_idx(draw_command_ref)]

	draw_command.desc.bind_group_layout_refs[0] = bind_group_layout_ref
	draw_command.desc.bind_group_layout_refs[1] = G_RENDERER.uniforms_bind_group_layout_ref
	draw_command.desc.bind_group_layout_refs[2] = G_RENDERER.globals_bind_group_layout_ref
	draw_command.desc.bind_group_layout_refs[3] = G_RENDERER.bindless_bind_group_layout_ref

	draw_command.desc.vert_shader_ref = find_shader_by_name("fullscreen.vert")
	draw_command.desc.frag_shader_ref = p_shader_ref
	draw_command.desc.draw_count = 3
	draw_command.desc.vertex_layout = .Empty

	draw_command_create(draw_command_ref, render_pass_ref)

	draw_command_set_bind_group(draw_command_ref, 0, bind_group_ref)
	draw_command_set_bind_group(draw_command_ref, 1, G_RENDERER.uniforms_bind_group_ref)
	draw_command_set_bind_group(draw_command_ref, 2, G_RENDERER.globals_bind_group_ref)
	draw_command_set_bind_group(draw_command_ref, 3, G_RENDERER.bindless_bind_group_ref)

	return GenericPixelJob {
			bind_group_layout_ref = bind_group_layout_ref,
			bind_group_ref = bind_group_ref,
			render_pass_ref = render_pass_ref,
			draw_command_ref = draw_command_ref,
		},
		true
}

//---------------------------------------------------------------------------//

@(private = "file")
create_bind_group_for_bindings :: proc(
	p_name: common.Name,
	p_render_pass_bindings: RenderPassBindings,
	p_is_compute: bool,
	p_is_compute_render_target_pass: bool,
	p_allocator: mem.Allocator,
) -> (
	BindGroupRef,
	BindGroupLayoutRef,
) {
	assert(p_is_compute_render_target_pass == false || (p_is_compute_render_target_pass && p_is_compute))

	shader_stage: ShaderStageFlags = {.Compute} if p_is_compute else {.Pixel}

	bindings_count :=
		u32(len(p_render_pass_bindings.image_inputs)) +
		u32(len(p_render_pass_bindings.buffer_inputs)) +
		u32(len(p_render_pass_bindings.buffer_outputs))

	if p_is_compute_render_target_pass {
		bindings_count += 1 // uniform buffer slot holding input texture size etc.
		bindings_count += u32(len(p_render_pass_bindings.image_outputs)) // for pixel path, these are handled via attachments
	}

	// Create the layout
	bind_group_layout_ref := allocate_bind_group_layout_ref(p_name, bindings_count)
	bind_group_layout := &g_resources.bind_group_layouts[get_bind_group_layout_idx(bind_group_layout_ref)]

	binding_index := 0

	// First entry for compute path contains the uniform buffer with the output texture size
	if p_is_compute_render_target_pass {
		bind_group_layout.desc.bindings[0].count = 1
		bind_group_layout.desc.bindings[0].shader_stages = shader_stage
		bind_group_layout.desc.bindings[0].type = .UniformBufferDynamic

		binding_index += 1
	}

	for buffer_input in p_render_pass_bindings.buffer_inputs {
		bind_group_layout.desc.bindings[binding_index].count = 1
		bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stage

		switch buffer_input.usage {
		case .Uniform:
			bind_group_layout.desc.bindings[binding_index].type = .UniformBufferDynamic
		case .General:
			bind_group_layout.desc.bindings[binding_index].type = .StorageBuffer
		}

		binding_index += 1
	}

	for _ in p_render_pass_bindings.buffer_outputs {
		bind_group_layout.desc.bindings[binding_index].count = 1
		bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stage
		bind_group_layout.desc.bindings[binding_index].type = .StorageBuffer

		binding_index += 1
	}

	for _ in p_render_pass_bindings.image_inputs {
		bind_group_layout.desc.bindings[binding_index].count = 1
		bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stage
		bind_group_layout.desc.bindings[binding_index].type = .Image

		binding_index += 1
	}

	if p_is_compute {
		for _ in p_render_pass_bindings.image_outputs {
			bind_group_layout.desc.bindings[binding_index].count = 1
			bind_group_layout.desc.bindings[binding_index].shader_stages = shader_stage
			bind_group_layout.desc.bindings[binding_index].type = .StorageImage

			binding_index += 1
		}
	}

	if create_bind_group_layout(bind_group_layout_ref) == false {
		destroy_bind_group_layout(bind_group_layout_ref)
		return InvalidBindGroupRef, InvalidBindGroupLayoutRef
	}

	// Create bind group
	bind_group_ref := allocate_bind_group_ref(p_name)
	bind_group := &g_resources.bind_groups[get_bind_group_idx(bind_group_ref)]

	bind_group.desc.layout_ref = bind_group_layout_ref

	if create_bind_group(bind_group_ref) == false {
		destroy_bind_group_layout(bind_group_layout_ref)
		return InvalidBindGroupRef, InvalidBindGroupLayoutRef
	}

	// Update the bind group
	buffers_count := 1 if p_is_compute_render_target_pass else 0
	buffers_count += len(p_render_pass_bindings.buffer_inputs)
	buffers_count += (len(p_render_pass_bindings.buffer_outputs))

	images_count := len(p_render_pass_bindings.image_outputs) if p_is_compute else 0
	images_count += len(p_render_pass_bindings.image_inputs)

	bind_group_update_info := BindGroupUpdate {
		buffers = make([]BindGroupBufferBinding, buffers_count, p_allocator),
		images  = make([]BindGroupImageBinding, images_count, p_allocator),
	}

	// Update the bind group with the images from the render tasks bindings
	if p_is_compute_render_target_pass {
		bind_group_update_info.buffers[0] = {
			binding    = 0,
			buffer_ref = g_uniform_buffers.transient_buffer.buffer_ref,
			size       = size_of(GenericComputeJobUniformData),
		}
	}

	binding_index = 1 if p_is_compute_render_target_pass else 0

	for input_buffer in p_render_pass_bindings.buffer_inputs {
		bind_group_update_info.buffers[binding_index] = BindGroupBufferBinding {
			binding    = u32(binding_index),
			buffer_ref = input_buffer.buffer_ref,
			// The offset is expected to be updated dynamically
			offset     = 0 if input_buffer.usage == .Uniform else input_buffer.offset,
			size       = input_buffer.size,
		}
		binding_index += 1
	}

	for output_buffer in p_render_pass_bindings.buffer_outputs {
		bind_group_update_info.buffers[binding_index] = BindGroupBufferBinding {
			binding    = u32(binding_index),
			buffer_ref = output_buffer.buffer_ref,
			offset     = output_buffer.offset,
			size       = output_buffer.size,
		}
		binding_index += 1
	}

	for input_image, i in p_render_pass_bindings.image_inputs {
		bind_group_update_info.images[i] = BindGroupImageBinding {
			binding     = u32(binding_index),
			image_ref   = input_image.image_ref,
			base_mip    = input_image.base_mip,
			base_array  = input_image.base_array_layer,
			mip_count   = input_image.mip_count,
			layer_count = input_image.array_layer_count,
		}

		if input_image.base_mip > 0 || input_image.base_array_layer > 0 {
			bind_group_update_info.images[i].flags += {.AddressSubresource}
		}

		binding_index += 1
	}

	num_input_images := len(p_render_pass_bindings.image_inputs)

	if p_is_compute {
		for output_image, i in p_render_pass_bindings.image_outputs {
			bind_group_update_info.images[num_input_images + i] = BindGroupImageBinding {
				binding     = u32(binding_index),
				image_ref   = output_image.image_ref,
				base_mip    = output_image.mip,
				base_array  = output_image.array_layer,
				mip_count   = 1,
				layer_count = 1,
				flags       = {.AddressSubresource},
			}

			binding_index += 1
		}
	}

	bind_group_update(bind_group_ref, bind_group_update_info)

	return bind_group_ref, bind_group_layout_ref
}

//---------------------------------------------------------------------------//

@(private)
generic_compute_job_destroy :: proc(p_job: GenericComputeJob) {
	compute_command_destroy(p_job.compute_command_ref)
	destroy_bind_group(p_job.bind_group_ref)
	destroy_bind_group_layout(p_job.bind_group_layout_ref)
}

//---------------------------------------------------------------------------//


@(private)
generic_pixel_job_destroy :: proc(p_job: GenericPixelJob) {
	destroy_bind_group(p_job.bind_group_ref)
	destroy_bind_group_layout(p_job.bind_group_layout_ref)
	draw_command_destroy(p_job.draw_command_ref)
	destroy_render_pass(p_job.render_pass_ref)
}

//---------------------------------------------------------------------------//

@(private)
generic_compute_job_update_uniform_data :: proc(p_resolution: Resolution) -> u32 {
	resolution := resolve_resolution(p_resolution)

	// Upload uniform data
	uniform_data := GenericComputeJobUniformData {
		texel_size   = glsl.vec2{1.0 / f32(resolution.x), 1.0 / f32(resolution.y)},
		texture_size = glsl.ivec2{i32(resolution.x), i32(resolution.y)},
	}

	return uniform_buffer_create_transient_buffer(&uniform_data)
}

//---------------------------------------------------------------------------//
