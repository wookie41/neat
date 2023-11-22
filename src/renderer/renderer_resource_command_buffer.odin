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
init_command_buffers :: proc(p_options: InitOptions) -> bool {
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
	return backend_init_command_buffers(p_options)
}

//---------------------------------------------------------------------------//

allocate_command_buffer_ref :: proc(p_name: common.Name) -> CommandBufferRef {
	ref := CommandBufferRef(
		common.ref_create(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_name),
	)
	g_resources.cmd_buffers[get_cmd_buffer_idx(ref)].desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_command_buffer :: #force_inline proc(p_ref: CommandBufferRef) -> bool {
	if backend_create_command_buffer(p_ref) == false {
		common.ref_free(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

get_cmd_buffer_idx :: #force_inline proc(p_ref: CommandBufferRef) -> u32 {
	return common.ref_get_idx(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)

}

//---------------------------------------------------------------------------//

destroy_command_buffer :: proc(p_ref: CommandBufferRef) {
	backend_destroy_command_buffer(p_ref)
	common.ref_free(&G_COMMAND_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

begin_command_buffer :: #force_inline proc(p_ref: CommandBufferRef) {
	backend_begin_command_buffer(p_ref)
}

//---------------------------------------------------------------------------//

end_command_buffer :: #force_inline proc(p_ref: CommandBufferRef) {
	backend_end_command_buffer(p_ref)
}

//---------------------------------------------------------------------------//
