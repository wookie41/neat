package common

import "core:hash"
import "core:mem"

//---------------------------------------------------------------------------//

when ODIN_OS == .Windows {
	dev_null := "NUL"
} else {
	dev_null := "/dev/null"
}

//---------------------------------------------------------------------------//

KILOBYTE :: 1024
MEGABYTE :: KILOBYTE * 1024
GIGABYTE :: MEGABYTE * 1024

//---------------------------------------------------------------------------//

StringTableEntry :: struct {
	str:       string,
	ref_count: u32,
}

@(private = "file")
INTERNAL: struct {
	string_table: map[Name]StringTableEntry,
}

//---------------------------------------------------------------------------//

init_names :: proc(p_string_allocator: mem.Allocator) {
	context.allocator = p_string_allocator
	INTERNAL.string_table = make(map[Name]StringTableEntry)
}

//---------------------------------------------------------------------------//

create_name :: proc(p_name: string) -> Name {
	assert(len(p_name) > 0)
	name: Name
	when ODIN_DEBUG {
		name = Name(hash.crc32(transmute([]u8)p_name))
	} else {
		name = Name(hash.crc32(transmute([]u8)p_name))
	}
	if name in INTERNAL.string_table {
		entry := &INTERNAL.string_table[name]
		entry.ref_count += 1
		return name
	}
	INTERNAL.string_table[name] = {
		str       = p_name,
		ref_count = 0,
	}
	return name
}

//---------------------------------------------------------------------------//

when ODIN_DEBUG {
	destroy_name :: #force_inline proc(p_name: Name) {
		assert(p_name in INTERNAL.string_table)
		entry := &INTERNAL.string_table[p_name]
		if entry.ref_count == 0 {
			delete_key(&INTERNAL.string_table, p_name)
		}
		entry.ref_count -= 1
	}
} else {
	destroy_name :: #force_inline proc(p_name: Name) {
	}
}


//---------------------------------------------------------------------------//

EMPTY_NAME := Name(0)

//---------------------------------------------------------------------------//

name_equal :: proc(p_name_1: Name, p_name_2: Name) -> bool {
	return p_name_1 == p_name_2
}

//---------------------------------------------------------------------------//


Name :: distinct u32

get_string :: proc(p_name: Name) -> string {
	when ODIN_DEBUG {
		assert(p_name in INTERNAL.string_table)
		return INTERNAL.string_table[p_name].str
	}
	return ""
}

//---------------------------------------------------------------------------//

hash_string_array :: proc(p_strings: []string) -> u32 {
	if len(p_strings) == 0 {
		return 0
	}
	h := hash.crc32(transmute([]u8)p_strings[0])
	for s in p_strings[1:] {
		h ~= hash.crc32(transmute([]u8)s)
	}
	return h
}
