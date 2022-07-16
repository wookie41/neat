package renderer

//---------------------------------------------------------------------------//

import c "core:c"
import "../common"

//---------------------------------------------------------------------------//

CommandBufferDesc :: struct {
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
	buffer: BufferRef,
	image:  ImageRef,
	// offsets at which data for each mip is stored in the buffer
	mip_buffer_offsets: []u32,
}

//---------------------------------------------------------------------------//

@(private)
init_command_buffers :: #force_inline proc(p_options: InitOptions) -> bool {
	G_COMMAND_BUFFER_REF_ARRAY = create_ref_array(
		CommandBufferResource,
		MAX_COMMAND_BUFFERS,
	)
	return backend_init_command_buffers(p_options)
}

//---------------------------------------------------------------------------//

@(private)
create_command_buffer :: #force_inline proc(
	p_cmd_buff_desc: CommandBufferDesc,
) -> CommandBufferRef {
	ref := CommandBufferRef(
		create_ref(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, common.EMPTY_NAME),
	)
	idx := get_ref_idx(ref)
	cmd_buff := &G_COMMAND_BUFFER_REF_ARRAY.resource_array[idx]

	if backend_create_command_buffer(p_cmd_buff_desc, cmd_buff) == false {
		free_ref(CommandBufferResource, &G_COMMAND_BUFFER_REF_ARRAY, ref)
		return InvalidCommandBufferRef
	}

	return ref
}

//---------------------------------------------------------------------------//

@(private)
get_command_buffer :: proc(p_ref: CommandBufferRef) -> ^CommandBufferResource {
	idx := get_ref_idx(p_ref)
	assert(idx < u32(len(G_COMMAND_BUFFER_REF_ARRAY.resource_array)))

	gen := get_ref_generation(p_ref)
	assert(gen == G_COMMAND_BUFFER_REF_ARRAY.generations[idx])

	return &G_COMMAND_BUFFER_REF_ARRAY.resource_array[idx]
}

//---------------------------------------------------------------------------//
