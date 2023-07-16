package engine

//---------------------------------------------------------------------------//

import "core:mem"
import "../common"
//---------------------------------------------------------------------------//

@(private = "file")
G_TEMP_ARENA_SIZE :: 16 * common.KILOBYTE

@(private = "file")
G_TOTAL_MEM_AVAILABLE :: 2 * common.GIGABYTE

//---------------------------------------------------------------------------//

@(private)
G_ALLOCATORS: struct {
	// Stack used to sub-allocate scratch arenas from that are used within a function scope 
	temp_arenas_stack:        mem.Stack,
	temp_arenas_allocator: mem.Allocator,
	// String allocator
	string_scratch_allocator:   mem.Scratch_Allocator,
	string_allocator:           mem.Allocator,
	main_allocator:             mem.Allocator,
}

//---------------------------------------------------------------------------//

MemoryInitOptions :: struct {
	total_available_memory: uint,
}

//---------------------------------------------------------------------------//

mem_init :: proc(p_options: MemoryInitOptions) {
	G_ALLOCATORS.main_allocator = context.allocator

	// String allocator
	mem.scratch_allocator_init(
		&G_ALLOCATORS.string_scratch_allocator,
		8 * common.MEGABYTE,
		mem.nil_allocator(),
	)
	G_ALLOCATORS.string_allocator = mem.scratch_allocator(
		&G_ALLOCATORS.string_scratch_allocator,
	)

	// Init the stack used for temp areans
	mem.stack_init(
		&G_ALLOCATORS.temp_arenas_stack,
		make([]byte, common.MEGABYTE * 8, context.allocator),
	)
	G_ALLOCATORS.temp_arenas_allocator = mem.stack_allocator(
		&G_ALLOCATORS.temp_arenas_stack,
	)
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
		make([]byte, G_TEMP_ARENA_SIZE, G_ALLOCATORS.temp_arenas_allocator),
	)
	p_temp_arena.allocator = mem.arena_allocator(&p_temp_arena.arena)
	return
}

//---------------------------------------------------------------------------//

temp_arena_delete :: proc(p_temp_arena: TempArena) {
	delete(p_temp_arena.arena.data, G_ALLOCATORS.temp_arenas_allocator)
}

//---------------------------------------------------------------------------//
