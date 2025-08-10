package renderer

//---------------------------------------------------------------------------//

import "../common"
import c "core:c"

//---------------------------------------------------------------------------//

CommandBufferDesc :: struct {
	name:   common.Name,
	flags:  CommandBufferFlags,
	thread: u8,
	frame:  u8,
}

//---------------------------------------------------------------------------//

@(private)
CommandBufferFlagBits :: enum u8 {
	Primary,
}

@(private)
CommandBufferFlags :: distinct bit_set[CommandBufferFlagBits;u8]

//---------------------------------------------------------------------------//

CommandBufferResource :: struct {
	desc:                     CommandBufferDesc,
}

//---------------------------------------------------------------------------//

CommandBufferRef :: common.Ref(CommandBufferResource)

//---------------------------------------------------------------------------//

InvalidCommandBufferRef := CommandBufferRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_COMMAND_BUFFER_REF_ARRAY: common.RefArray(CommandBufferResource)

//---------------------------------------------------------------------------//

@(private)
command_buffer_init :: proc(p_options: InitOptions) -> bool {
	G_COMMAND_BUFFER_REF_ARRAY = common.ref_array_create(
		CommandBufferResource,
		MAX_COMMAND_BUFFERS,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.cmd_buffers = make_soa(
		#soa[]CommandBufferResource,
		MAX_COMMAND_BUFFERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_cmd_buffers = make_soa(
		#soa[]BackendCommandBufferResource,
		MAX_COMMAND_BUFFERS,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	return backend_command_buffer_end_init(p_options)
}

//---------------------------------------------------------------------------//

command_buffer_allocate :: proc(p_name: common.Name) -> CommandBufferRef {
	ref := CommandBufferRef(
		common.ref_create(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_name),
	)
	g_resources.cmd_buffers[command_buffer_get_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

command_buffer_create :: #force_inline proc(p_ref: CommandBufferRef) -> bool {
	if backcommand_buffer_end_create(p_ref) == false {
		common.ref_free(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

command_buffer_get_idx :: #force_inline proc(p_ref: CommandBufferRef) -> u32 {
	return common.ref_get_idx(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)

}

//---------------------------------------------------------------------------//

command_buffer_destroy :: proc(p_ref: CommandBufferRef) {
	backend_command_buffer_end_destroy(p_ref)
	common.ref_free(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

command_buffer_begin :: #force_inline proc(p_ref: CommandBufferRef) {
	backend_command_buffer_end_begin(p_ref)
}

//---------------------------------------------------------------------------//

command_buffer_end :: #force_inline proc(p_ref: CommandBufferRef) {
	backend_command_buffer_end_end(p_ref)
}

//---------------------------------------------------------------------------//
