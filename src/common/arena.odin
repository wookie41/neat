package common

//---------------------------------------------------------------------------//

import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
DEFAULT_TEMP_ARENA_SIZE :: 16 * KILOBYTE

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

Arena :: struct {
	scratch_allocator: mem.Scratch_Allocator,
	allocator:         mem.Allocator,
	src_allocator:     mem.Allocator,
}

//---------------------------------------------------------------------------//

arena_init :: proc(p_arena: ^Arena, p_arena_size: u32, p_allocator: mem.Allocator) {
	mem.scratch_allocator_init(&p_arena.scratch_allocator, int(p_arena_size), p_allocator)
	p_arena.allocator = mem.scratch_allocator(&p_arena.scratch_allocator)
	p_arena.src_allocator = p_allocator
	return
}

//---------------------------------------------------------------------------//

arena_delete :: proc(p_arena: Arena) {
	delete(p_arena.scratch_allocator.data, p_arena.src_allocator)
}

//---------------------------------------------------------------------------//

temp_arena_init :: proc(p_arena: ^Arena, p_arena_size: u32 = DEFAULT_TEMP_ARENA_SIZE) {
	arena_init(p_arena, p_arena_size, INTERNAL.temp_arenas_allocator)
}

//---------------------------------------------------------------------------//
