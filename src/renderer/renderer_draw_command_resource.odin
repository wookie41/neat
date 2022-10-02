package renderer

//---------------------------------------------------------------------------//

import c "core:c"
import "../common"

//---------------------------------------------------------------------------//

DrawCommandFlagBits :: enum u32 {
	FrameAllocated,
}

DrawCommandFlags :: distinct bit_set[DrawCommandFlagBits;u32]

//---------------------------------------------------------------------------//

DrawCommandDesc :: struct {
	pipeline:      PipelineRef,
	bind_groups:   []BindGroup,
	vertex_buffer: BufferRef,
	index_buffer:  BufferRef,
	vertex_count:  u32,
	index_count:   u32,
	flags:         DrawCommandFlags,
}

DrawCommandResource :: struct {
	using backend_draw_command: BackendDrawCommandResource,
	desc:                       DrawCommandDesc,
}

//---------------------------------------------------------------------------//

DrawCommandRef :: Ref(RenderPassResource)

//---------------------------------------------------------------------------//

InvalidDrawCommandRef := RenderPassRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_DRAW_FRAME_ALLOCATED_COMMAND_REF_ARRAY: RefArray(DrawCommandResource)

//---------------------------------------------------------------------------//

@(private = "file")
G_DRAW_PERSISTENT_COMMAND_REF_ARRAY: RefArray(DrawCommandResource)

//---------------------------------------------------------------------------//

allocate_persistent_draw_command_ref :: proc() -> DrawCommandRef {
	ref := DrawCommandRef(
		create_ref(DrawCommandResource, &G_DRAW_PERSISTENT_COMMAND_REF_ARRAY, common.EMPTY_NAME),
	)
	draw_command := get_draw_command(ref)
	return ref
}
//---------------------------------------------------------------------------//

allocate_frame_allocated_draw_command_ref :: proc() -> DrawCommandRef {
	ref := DrawCommandRef(
		create_ref(DrawCommandResource, &G_DRAW_FRAME_ALLOCATED_COMMAND_REF_ARRAY, common.EMPTY_NAME),
	)
	draw_command := get_draw_command(ref)
	draw_command.desc.flags = {.FrameAllocated}
	return ref
}

//---------------------------------------------------------------------------//

create_draw_command :: proc(p_ref: DrawCommandRef) -> bool {
	draw_command := get_draw_command(p_ref)
	if backend_create_draw_command(p_ref, draw_command) == false {
		if .FrameAllocated in draw_command.desc.flags {
			free_ref(DrawCommandResource, &G_DRAW_FRAME_ALLOCATED_COMMAND_REF_ARRAY, ref)
		} else {
			free_ref(DrawCommandResource, &G_DRAW_PERSISTENT_COMMAND_REF_ARRAY, ref)
		}
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

get_draw_command :: proc(p_ref: DrawCommandRef) -> ^DrawCommandResource {
	if .FrameAllocated in draw_command.desc.flags {
		return get_resource(
			DrawCommandResource,
			&G_DRAW_FRAME_ALLOCATED_COMMAND_REF_ARRAY,
			p_ref,
		)
	} else {
		return get_resource(DrawCommandResource, &G_DRAW_COMMAND_REF_ARRAY, p_ref)
	}
}

//---------------------------------------------------------------------------//

destroy_draw_command :: proc(p_ref: DrawCommandRef) {
	draw_comand := get_draw_command(p_ref)
	backend_destroy_draw_command(draw_command)
	if .FrameAllocated in draw_command.desc.flags {
		free_ref(DrawCommandResource, &G_DRAW_FRAME_ALLOCATED_COMMAND_REF_ARRAY, p_ref)
	} else {
		free_ref(DrawCommandResource, &G_DRAW_PERSISTENT_COMMAND_REF_ARRAY, p_ref)
	}
}

//---------------------------------------------------------------------------//
