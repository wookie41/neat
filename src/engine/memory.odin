package engine

//---------------------------------------------------------------------------//

import "../common"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
G_TOTAL_MEM_AVAILABLE :: 2 * common.GIGABYTE

//---------------------------------------------------------------------------//

@(private)
G_ALLOCATORS: struct {
	// String allocator
	string_scratch_allocator: mem.Scratch_Allocator,
	string_allocator:         mem.Allocator,
	main_allocator:           mem.Allocator,
	asset_allocator:          mem.Allocator,
}

//---------------------------------------------------------------------------//

MemoryInitOptions :: struct {
	total_available_memory: uint,
}

//---------------------------------------------------------------------------//

mem_init :: proc(p_options: MemoryInitOptions) {
	G_ALLOCATORS.main_allocator = context.allocator
	G_ALLOCATORS.asset_allocator = context.allocator

	// String allocator
	mem.scratch_allocator_init(
		&G_ALLOCATORS.string_scratch_allocator,
		32 * common.MEGABYTE,
		G_ALLOCATORS.main_allocator,
	)
	G_ALLOCATORS.string_allocator = mem.scratch_allocator(&G_ALLOCATORS.string_scratch_allocator)
	common.temp_arenas_init_stack(32 * common.MEGABYTE, G_ALLOCATORS.main_allocator)
}

//---------------------------------------------------------------------------//