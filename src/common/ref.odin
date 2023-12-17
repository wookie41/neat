package common

//---------------------------------------------------------------------------//

import "core:c"
import "core:mem"

//---------------------------------------------------------------------------//

RefArray :: struct($ResourceType: typeid) {
	next_idx:         u32,
	num_free_indices: u32,
	free_indices:     []u32,
	generations:      []u8,
	names:            []Name,
	alive_refs:       []Ref(ResourceType),
	alive_count:      u32,
	allocator:        mem.Allocator,
}

//---------------------------------------------------------------------------//

Ref :: struct($T: typeid) {
	ref: u32,
}

//---------------------------------------------------------------------------//

ref_is_alive :: #force_inline proc(p_ref_array: ^RefArray($R), p_ref: Ref(R)) -> bool {
	idx := u32(p_ref.ref >> 24)

	gen := ref_get_generation(p_ref)
	if gen != p_ref_array.generations[idx] {
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

ref_get_idx :: #force_inline proc(p_ref_array: ^RefArray($R), p_ref: Ref(R)) -> u32 {
	idx := u32(p_ref.ref >> 24)
	assert(idx < p_ref_array.next_idx)

	gen := ref_get_generation(p_ref)
	assert(gen == p_ref_array.generations[idx])

	return idx
}

//---------------------------------------------------------------------------//

ref_get_generation :: #force_inline proc(p_ref: $T) -> u8 {
	return u8(p_ref.ref & 0xFF)
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
			generations = make([]u8, p_capacity, p_allocator),
			names = make([]Name, p_capacity, p_allocator),
			next_idx = 0,
			num_free_indices = 0,
			alive_refs = make([]Ref(R), p_capacity, p_allocator),
			alive_count = 0,
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
	generation := u32(0)
	if p_ref_array.num_free_indices > 0 {
		p_ref_array.num_free_indices -= 1
		idx = p_ref_array.free_indices[p_ref_array.num_free_indices]
		p_ref_array.generations[idx] += 1
		generation = u32(p_ref_array.generations[idx])
	} else {
		idx = p_ref_array.next_idx
		p_ref_array.next_idx += 1
	}

	new_ref := Ref(R) {
		ref = (idx << 24) | (generation & 0xFF),
	}

	p_ref_array.names[idx] = p_name
	p_ref_array.alive_refs[p_ref_array.alive_count] = new_ref
	p_ref_array.alive_count += 1

	return new_ref
}

//---------------------------------------------------------------------------//

ref_free :: proc(p_ref_array: ^RefArray($R), p_ref: Ref(R)) {
	assert(p_ref_array.num_free_indices < u32(len(p_ref_array.free_indices)))
	p_ref_array.free_indices[p_ref_array.num_free_indices] = ref_get_idx(p_ref_array, p_ref)
	p_ref_array.generations[p_ref_array.num_free_indices] = ref_get_generation(p_ref)
	p_ref_array.num_free_indices += 1
	p_ref_array.names[ref_get_idx(p_ref_array, p_ref)] = 0

	for i in 0 ..< p_ref_array.alive_count {
		if p_ref_array.alive_refs[i] == p_ref {
			// Swap the last element with the removed element
			p_ref_array.alive_refs[i] = p_ref_array.alive_refs[p_ref_array.alive_count - 1]
			break
		}
	}

	p_ref_array.alive_count -= 1
}

//---------------------------------------------------------------------------//

ref_find_by_name :: proc(p_ref_array: ^RefArray($R), p_name: Name) -> Ref(R) {
	for name, idx in p_ref_array.names {
		if name_equal(name, p_name) {
			return Ref(R){ref = u32(idx) << 24 | u32(p_ref_array.generations[idx])}
		}
	}

	return Ref(R){ref = c.UINT32_MAX}
}
//---------------------------------------------------------------------------//

ref_array_clear :: proc(p_ref_array: ^RefArray($R)) {
	capacity := len(p_ref_array.generations)

	delete(p_ref_array.free_indices)
	delete(p_ref_array.generations)
	p_ref_array.alive_count = 0
	p_ref_array.free_indices = make([]u32, capacity, p_ref_array.allocator)
	p_ref_array.generations = make([]u8, capacity, p_ref_array.allocator)
	p_ref_array.next_idx = 0
	p_ref_array.num_free_indices = 0
}

//---------------------------------------------------------------------------//
