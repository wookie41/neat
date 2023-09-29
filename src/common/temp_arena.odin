package common

//---------------------------------------------------------------------------//

import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
G_TEMP_ARENA_SIZE :: 16 * KILOBYTE

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	// Stack used to sub-allocate scratch arenas from that are used within a function scope 
	temp_arenas_stack:     mem.Stack,
	temp_arenas_allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

temp_arenas_init_stack :: proc(p_arenas_size: u32, p_allocator: mem.Allocator) {
	// Init the stack used for temp areans
	mem.stack_init(&INTERNAL.temp_arenas_stack, make([]byte, p_arenas_size, p_allocator))
	INTERNAL.temp_arenas_allocator = mem.stack_allocator(&INTERNAL.temp_arenas_stack)
}

//---------------------------------------------------------------------------//

TempArena :: struct {
	arena:     mem.Arena,
	allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

temp_arena_init :: proc(p_temp_arena: ^TempArena) {
	mem.arena_init(
		&p_temp_arena.arena,
		make([]byte, G_TEMP_ARENA_SIZE, INTERNAL.temp_arenas_allocator),
	)
	p_temp_arena.allocator = mem.arena_allocator(&p_temp_arena.arena)
	return
}

//---------------------------------------------------------------------------//

temp_arena_delete :: proc(p_temp_arena: TempArena) {
	delete(p_temp_arena.arena.data, INTERNAL.temp_arenas_allocator)
}

//---------------------------------------------------------------------------//
