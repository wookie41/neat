
package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:math/linalg/glsl"

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
	p_bindings: []Binding,
) -> (
	out_job: GenericComputeJob,
	out_success: bool,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	bind_group_ref, bind_group_layout_ref := bind_group_create_for_bindings(
		p_name,
		p_bindings,
		true,
	)

	// Create the compute command
	compute_command_ref := compute_command_allocate(p_name, 4, 0)
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
	p_bindings: []Binding,
	p_render_pass_outputs: []RenderPassOutput,
	p_resolution: glsl.uvec2,
) -> (
	out_job: GenericPixelJob,
	out_success: bool,
) {
	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	// Create a render pass based on output images
	render_pass_ref := render_pass_allocate(p_name, len(p_render_pass_outputs))
	render_pass := &g_resources.render_passes[render_pass_get_idx(render_pass_ref)]
	render_pass.desc.depth_stencil_type = .None
	render_pass.desc.primitive_type = .TriangleList
	render_pass.desc.resterizer_type = .Default
	render_pass.desc.multisampling_type = ._1
	render_pass.desc.resolution = p_resolution

	for output_image, i in p_render_pass_outputs {
		image := &g_resources.images[image_get_idx(output_image.image_ref)]
		render_pass.desc.layout.render_target_formats[i] = image.desc.format
		render_pass.desc.layout.render_target_blend_types[i] = .Default
	}

	render_pass_create(render_pass_ref) or_return

	bind_group_ref, bind_group_layout_ref := bind_group_create_for_bindings(
		p_name,
		p_bindings,
		false,
	)

	// Create the draw command
	draw_command_ref := draw_command_allocate(p_name, 4, 0)
	draw_command := &g_resources.draw_commands[draw_command_get_idx(draw_command_ref)]
	draw_command.desc.vert_shader_ref = shader_find_by_name("fullscreen.vert")
	draw_command.desc.frag_shader_ref = p_shader_ref
	draw_command.desc.draw_count = 3
	draw_command.desc.vertex_layout = .Empty
	draw_command.desc.bind_group_layout_refs = {
		bind_group_layout_ref,
		G_RENDERER.uniforms_bind_group_layout_ref,
		G_RENDERER.globals_bind_group_layout_ref,
		G_RENDERER.bindless_bind_group_layout_ref,
	}

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

@(private)
generic_compute_job_destroy :: proc(p_job: GenericComputeJob) {
	compute_command_destroy(p_job.compute_command_ref)
	bind_group_layout_destroy(p_job.bind_group_layout_ref)
	bind_group_destroy(p_job.bind_group_ref)
}

//---------------------------------------------------------------------------//


@(private)
generic_pixel_job_destroy :: proc(p_job: GenericPixelJob) {
	bind_group_destroy(p_job.bind_group_ref)
	bind_group_layout_destroy(p_job.bind_group_layout_ref)
	draw_command_destroy(p_job.draw_command_ref)
	render_pass_destroy(p_job.render_pass_ref)
}

//---------------------------------------------------------------------------//

@(private)
generic_compute_job_create_uniform_data :: proc(p_resolution: Resolution) -> u32 {
	resolution := resolve_resolution(p_resolution)

	// Upload uniform data
	uniform_data := GenericComputeJobUniformData {
		texel_size   = glsl.vec2{1.0 / f32(resolution.x), 1.0 / f32(resolution.y)},
		texture_size = glsl.ivec2{i32(resolution.x), i32(resolution.y)},
	}

	return uniform_buffer_create_transient_buffer(&uniform_data)
}

//---------------------------------------------------------------------------//
