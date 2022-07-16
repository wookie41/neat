package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "../common"

//---------------------------------------------------------------------------//

// ResourceType :: enum u16 {
// 	SHADER,
// 	PIPELINE_LAYOUT,
// 	IMAGE,
// 	BUFFER,
// 	RENDER_PASS,
// 	PIPELINE,
// }

//---------------------------------------------------------------------------//

RefArray :: struct(ResourceType: typeid) {
	resource_array:   []ResourceType,
	next_idx:         u32,
	num_free_indices: u32,
	free_indices:     []u32,
	generations:      []u16,
	names:            []u32,
}

RefArraySOA :: struct(ResourceType: typeid) {
	resource_array:   #soa[]ResourceType,
	next_idx:         u32,
	num_free_indices: u32,
	free_indices:     []u32,
	generations:      []u16,
}


//---------------------------------------------------------------------------//

Ref :: struct($T: typeid) {
	ref:  u64,
	name: common.Name,
}

//---------------------------------------------------------------------------//

get_ref_idx :: #force_inline proc(p_ref: $T) -> u32 {
	return u32(p_ref.ref >> 32)
}

//---------------------------------------------------------------------------//

get_ref_generation :: #force_inline proc(p_ref: $T) -> u16 {
	return u16(p_ref.ref)
}

//---------------------------------------------------------------------------//

create_ref_array :: proc($R: typeid, p_capacity: u32) -> RefArray(R) {
	return RefArray(R){
		free_indices = make([]u32, p_capacity),
		generations = make([]u16, p_capacity),
		names = make([]u32, p_capacity),
		next_idx = 0,
		num_free_indices = 0,
	}
}

//---------------------------------------------------------------------------//

create_ref_array_soa :: proc($R: typeid, p_capacity: u32) -> RefArray(R) {
	return RefArraySOA(R){
		free_indices = make([]u32, p_capacity),
		generations = make([]u16, p_capacity),
		names = make([]u32, p_capacity),
		next_idx = 0,
		num_free_indices = 0,
		resource_array = make(
			[]p_resource_type,
			p_capacity,
			G_RENDERER_ALLOCATORS.resource_allocator,
		),
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
create_ref_aos :: proc($R: typeid, p_ref_array: ^RefArray(R), p_name: common.Name) -> Ref(R) {
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

	return Ref(R){name = p_name, ref = u64(idx) << 32 | generation}
}

//---------------------------------------------------------------------------//

@(private = "file")
create_ref_soa :: proc($R: typeid, p_ref_array: ^RefArraySOA(R), p_name: common.Name) -> Ref(R) {
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

	return Ref(R){name = p_name, ref = u64(idx) << 32 | generation}
}

//---------------------------------------------------------------------------//

@(private = "file")
free_ref_aos :: proc($R: typeid, p_ref_array: ^RefArray(R), p_ref: Ref(R)) {
	assert(p_ref_array.num_free_indices < u32(len(p_ref_array.free_indices)))
	p_ref_array.free_indices[p_ref_array.num_free_indices] = get_ref_idx(p_ref)
	p_ref_array.generations[p_ref_array.num_free_indices] = get_ref_generation(p_ref)
	p_ref_array.num_free_indices += 1
	p_ref_array.names[get_ref_idx(p_ref)] = 0
}

//---------------------------------------------------------------------------//

@(private = "file")
free_ref_soa :: proc($R :typeid, p_ref_array: ^RefArraySOA(R), p_ref: Ref(R)) {
	assert(p_ref_array.num_free_indices < u32(len(p_ref_array.free_indices)))
	p_ref_array.free_indices[p_ref_array.num_free_indices] = get_ref_idx(p_ref)
	p_ref_array.generations[p_ref_array.num_free_indices] = get_ref_generation(p_ref)
	p_ref_array.num_free_indices += 1
	p_ref_array.names[get_ref_idx(p_ref)] = 0
}

//---------------------------------------------------------------------------//

@(private = "file")
find_ref_by_name_aos :: proc($R: typeid, p_ref_array: ^RefArray(R), p_name: common.Name) -> Ref(R) {
	for name, idx in p_ref_array.names {
		if common.name_equal(name, p_name) {
			return Ref(R){
				name = p_name,
				ref = u64(idx) << 32 | u64(p_ref_array.generations[idx]),
			}
		}
	}

	return Ref(R){ref=c.UINT64_MAX}
}
//---------------------------------------------------------------------------//

@(private = "file")
find_ref_by_name_soa :: proc($R :typeid, p_ref_array: ^RefArraySOA(R), p_name: common.Name) -> (Ref(R), bool) {
	for name, idx in p_ref_array.names {
		if common.name_equal(name, p_name) {
			return Ref(R){
				name = p_name,
				ref = u64(idx) << 32 | u64(p_ref_array.generations[idx]),
			}, true
		}
	}

	return nil, false
}
//---------------------------------------------------------------------------//

create_ref :: proc {
	create_ref_aos,
	create_ref_soa,
}
free_ref :: proc {
	free_ref_aos,
	free_ref_soa,
}
find_ref_by_name :: proc {
	find_ref_by_name_aos,
	find_ref_by_name_soa,
}

//---------------------------------------------------------------------------//
