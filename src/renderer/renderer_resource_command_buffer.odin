package renderer

//---------------------------------------------------------------------------//

import c "core:c"
import "../common"

//---------------------------------------------------------------------------//

CommandBufferDesc :: struct {
	name:   common.Name,
	flags:  CommandBufferFlags,
	thread: u8,
	frame:  u8,
}

//---------------------------------------------------------------------------//


@(private)
CommandBuffer :: distinct u32

//---------------------------------------------------------------------------//

@(private)
CommandBufferFlagBits :: enum u8 {
	Primary,
}

@(private)
CommandBufferFlags :: distinct bit_set[CommandBufferFlagBits;u8]

//---------------------------------------------------------------------------//

CommandBufferResource :: struct {
	using backend_cmd_buffer: BackendCommandBufferResource,
	desc:                     CommandBufferDesc,
}

//---------------------------------------------------------------------------//

CommandBufferRef :: Ref(CommandBufferResource)

//---------------------------------------------------------------------------//

InvalidCommandBufferRef := CommandBufferRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_COMMAND_BUFFER_REF_ARRAY: RefArray(CommandBufferResource)

//---------------------------------------------------------------------------//

@(private)
TextureCopy :: struct {
	buffer:             BufferRef,
	image:              ImageRef,
	// offsets at which data for each mip is stored in the buffer
	mip_buffer_offsets: []u32,
}

//---------------------------------------------------------------------------//

@(private)
init_command_buffers :: #force_inline proc(p_options: InitOptions) -> bool {
	G_COMMAND_BUFFER_REF_ARRAY = create_ref_array(CommandBufferResource, MAX_COMMAND_BUFFERS)
	return backend_init_command_buffers(p_options)
}

//---------------------------------------------------------------------------//

allocate_command_buffer_ref :: proc(p_name: common.Name) -> CommandBufferRef {
	ref := CommandBufferRef(
		create_ref(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_name),
	)
	get_command_buffer(ref).desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

create_command_buffer :: #force_inline proc(
	p_ref: CommandBufferRef,
) -> bool {
	cmd_buff := get_command_buffer(p_ref)

	if backend_create_command_buffer(p_ref, cmd_buff) == false {
		free_ref(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_command_buffer :: proc(p_ref: CommandBufferRef) -> ^CommandBufferResource {
	return get_resource(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

destroy_command_buffer :: proc(p_ref: CommandBufferRef) {
	cmd_buff := get_command_buffer(p_ref)
	backend_destroy_command_buffer(cmd_buff)
	free_ref(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

begin_command_buffer :: #force_inline proc(p_ref: CommandBufferRef) {
	cmd_buff := get_command_buffer(p_ref)
	backend_begin_command_buffer(p_ref, cmd_buff)
}

//---------------------------------------------------------------------------//

end_command_buffer :: #force_inline proc(p_ref: CommandBufferRef) {
	cmd_buff := get_command_buffer(p_ref)
	backend_end_command_buffer(p_ref, cmd_buff)
}

//---------------------------------------------------------------------------//
