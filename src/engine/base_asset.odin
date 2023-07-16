package engine

import "core:time"
import "core:math/rand"
import "core:strings"
import "core:fmt"
import "../common"

//---------------------------------------------------------------------------//

AssetType :: enum {
	Texture,
	Mesh,
}

//---------------------------------------------------------------------------//

AssetBase :: struct {
	name: common.Name,
	uuid: UUID,
    type: AssetType,
}

//---------------------------------------------------------------------------//

@(private = "file")
UUID_Union :: struct #raw_union {
	using _: struct #packed {
		time_low:                           u32,
		time_mid:                           u16,
		time_hi_and_version:                u16,
		clock_seq_hi_and_res_clock_seq_low: u16,
		node:                               [3]u16,
	},
	raw:     u128,
}

//---------------------------------------------------------------------------//

#assert(size_of(UUID_Union) == size_of(u128))
UUID :: u128

//---------------------------------------------------------------------------//

uuid_create :: proc(version: u16 = 0) -> UUID {
	return uuid_create_union(version).raw
}

//---------------------------------------------------------------------------//

@(private = "file")
uuid_create_union :: proc(version: u16 = 0) -> UUID_Union {
	// RFC 4122 - Loosely based on version 4.2
	v := version == 0 ? u16(rand.uint32()) : version // if no version passed in, generate a random one
	cs := u16(rand.uint32())
	n: [3]u16 = {u16(rand.uint32()), u16(rand.uint32()), u16(rand.uint32())}
	t := time.now()

	u: UUID_Union
	u.time_low = u32(t._nsec & 0x00000000ffffffff)
	u.time_mid = u16((t._nsec & 0x000000ffff000000) >> 24)
	u.time_hi_and_version = u16(u16(t._nsec >> 52) | v)
	u.clock_seq_hi_and_res_clock_seq_low = cs
	u.node = n

	return u
}

//---------------------------------------------------------------------------//

uuid_create_string :: proc(version: u16 = 0, allocator := context.allocator) -> string {
	using strings

	uuid := uuid_create_union(version)

	sb := builder_make(allocator)
	builder_grow(&sb, 38)
	defer builder_destroy(&sb)

	fmt.sbprintf(
		&sb,
		"{{%08x-%04x-%04x-%04x-%04x%04x%04x}",
		uuid.time_low,
		uuid.time_mid,
		uuid.time_hi_and_version,
		uuid.clock_seq_hi_and_res_clock_seq_low,
		uuid.node[0],
		uuid.node[1],
		uuid.node[2],
	)

	return to_string(sb)
}

//---------------------------------------------------------------------------//
