package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "../common"

//---------------------------------------------------------------------------//

ResourceType :: enum u16 {
	SHADER,
	PIPELINE_LAYOUT,
}

//---------------------------------------------------------------------------//

RefArray :: struct {
	res_type:         ResourceType,
	next_idx:         u32,
	num_free_indices: u32,
	free_indices:     []u32,
	generations:      []u16,
	names: 			  []u32,
}

//---------------------------------------------------------------------------//

Ref :: struct {
	ref:  u64,
	name: common.Name,
}

//---------------------------------------------------------------------------//

InvalidRef := Ref {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

get_ref_idx :: #force_inline proc(p_ref: $T) -> u32 {
	return u32(p_ref.ref >> 32)
}

//---------------------------------------------------------------------------//

get_ref_res_type :: #force_inline proc(p_ref: Ref) -> ResourceType {
	return ResourceType(u16(p_ref.ref >> 16))
}

//---------------------------------------------------------------------------//

get_ref_generation :: #force_inline proc(p_ref: Ref) -> u16 {
	return u16(p_ref.ref)
}

//---------------------------------------------------------------------------//

create_ref_array :: proc(p_res_type: ResourceType, p_capacity: u32) -> RefArray {
	return RefArray{
		free_indices = make([]u32, p_capacity),
		generations = make([]u16, p_capacity),
		names = make([]u32, p_capacity),
		next_idx = 0,
		res_type = p_res_type,
		num_free_indices = 0,
	}
}

//---------------------------------------------------------------------------//

create_ref :: proc(p_ref_array: ^RefArray, p_name: common.Name) -> Ref {
	assert(
		p_ref_array.next_idx <
		u32(len(p_ref_array.free_indices)) ||
		len(p_ref_array.free_indices) >
		0,
	)

	idx := u32(0)
	generation := u64(0)
	if p_ref_array.num_free_indices > 0 {
		p_ref_array.num_free_indices -= 1
		idx = p_ref_array.free_indices[p_ref_array.num_free_indices]
		generation = u64(p_ref_array.generations[p_ref_array.num_free_indices] + 1)
	} else {
		idx = p_ref_array.next_idx
		p_ref_array.next_idx += 1
	}

	p_ref_array.names[idx] = p_name.hash

	return Ref{
		name = p_name,
		ref = u64(idx) << 32 | u64(p_ref_array.res_type) << 16 | generation,
	}
}

//---------------------------------------------------------------------------//

free_ref :: proc(p_ref_array: ^RefArray, p_ref: Ref) {
	assert(p_ref_array.res_type == ResourceType(get_ref_res_type(p_ref)))
	assert(p_ref_array.num_free_indices < u32(len(p_ref_array.free_indices)))
	p_ref_array.free_indices[p_ref_array.num_free_indices] = get_ref_idx(p_ref)
	p_ref_array.generations[p_ref_array.num_free_indices] = get_ref_generation(p_ref)
	p_ref_array.num_free_indices += 1
	p_ref_array.names[get_ref_idx(p_ref)] = 0
}

//---------------------------------------------------------------------------//

find_ref_by_name :: proc(p_ref_array: ^RefArray, p_name: common.Name) -> Ref {
	for name, idx in p_ref_array.names {
		if common.name_equal(name, p_name) {
			return Ref{
				name = p_name,
				ref = u64(idx) << 32 | u64(p_ref_array.res_type) << 16 | u64(p_ref_array.generations[idx]),
			}
		}
	}

	return InvalidRef
}
//---------------------------------------------------------------------------//
