package common

//---------------------------------------------------------------------------//

import "core:c"
import "core:mem"

//---------------------------------------------------------------------------//

RefArray :: struct($ResourceType: typeid) {
	next_idx:         u32,
	num_free_indices: u32,
	free_indices:     []u32,
	generations:      []u16,
	names:            []Name,
	alive_refs:       [dynamic]Ref(ResourceType),
	allocator:        mem.Allocator,
}

//---------------------------------------------------------------------------//

Ref :: struct($T: typeid) {
	ref:  u64,
	name: Name,
}

//---------------------------------------------------------------------------//

ref_get_idx :: #force_inline proc(p_ref_array: ^RefArray($R), p_ref: Ref(R)) -> u32 {
	idx := u32(p_ref.ref >> 32)
	assert(idx < p_ref_array.next_idx)

	gen := ref_get_generation(p_ref)
	assert(gen == p_ref_array.generations[idx])

	return idx
}

//---------------------------------------------------------------------------//

ref_get_generation :: #force_inline proc(p_ref: $T) -> u16 {
	return u16(p_ref.ref)
}

//---------------------------------------------------------------------------//
	
ref_array_create :: proc(
	$R: typeid,
	p_capacity: int,
	p_allocator: mem.Allocator = context.allocator,
) -> RefArray(R) {
	return(
		RefArray(R){
			free_indices = make([]u32, p_capacity, p_allocator),
			generations = make([]u16, p_capacity, p_allocator),
			names = make([]Name, p_capacity, p_allocator),
			next_idx = 0,
			num_free_indices = 0,
			alive_refs = make([dynamic]Ref(R), p_capacity, p_allocator),
			allocator = p_allocator,
		} \
	)
}

ref_create :: proc($R: typeid, p_ref_array: ^RefArray(R), p_name: Name) -> Ref(R) {
	assert(
		p_ref_array.next_idx < u32(len(p_ref_array.free_indices)) ||
		len(p_ref_array.free_indices) > 0,
	)

	idx := u32(0)
	generation := u64(0)
	if p_ref_array.num_free_indices > 0 {
		p_ref_array.num_free_indices -= 1
		idx = p_ref_array.free_indices[p_ref_array.num_free_indices]
		p_ref_array.generations[idx] += 1
		generation = u64(p_ref_array.generations[idx])
	} else {
		idx = p_ref_array.next_idx
		p_ref_array.next_idx += 1
	}

	p_ref_array.names[idx] = p_name

	return Ref(R){name = p_name, ref = u64(idx) << 32 | generation}
}

//---------------------------------------------------------------------------//

ref_free :: proc(p_ref_array: ^RefArray($R), p_ref: Ref(R)) {
	assert(p_ref_array.num_free_indices < u32(len(p_ref_array.free_indices)))
	p_ref_array.free_indices[p_ref_array.num_free_indices] = ref_get_idx(p_ref_array, p_ref)
	p_ref_array.generations[p_ref_array.num_free_indices] = ref_get_generation(p_ref)
	p_ref_array.num_free_indices += 1
	p_ref_array.names[ref_get_idx(p_ref_array, p_ref)] = 0
	destroy_name(p_ref.name)
}

//---------------------------------------------------------------------------//

ref_find_by_name :: proc(p_ref_array: ^RefArray($R), p_name: Name) -> Ref(R) {
	for name, idx in p_ref_array.names {
		if name_equal(name, p_name) {
			return Ref(R){name = p_name, ref = u64(idx) << 32 | u64(p_ref_array.generations[idx])}
		}
	}

	return Ref(R){ref = c.UINT64_MAX}
}
//---------------------------------------------------------------------------//

ref_array_clear :: proc(p_ref_array: ^RefArray($R)) {
	capacity := len(p_ref_array.generations)

	delete(p_ref_array.free_indices)
	delete(p_ref_array.generations)
	clear(&p_ref_array.alive_refs)
	p_ref_array.free_indices = make([]u32, capacity, p_ref_array.allocator)
	p_ref_array.generations = make([]u16, capacity, p_ref_array.allocator)
	p_ref_array.next_idx = 0
	p_ref_array.num_free_indices = 0
}

//---------------------------------------------------------------------------//