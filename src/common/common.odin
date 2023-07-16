package common

import "core:hash"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:fmt"


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

Name :: distinct u32
@(private = "file")
INTERNAL: struct {
	string_table: map[Name]string,
}

//---------------------------------------------------------------------------//

init_names :: proc(p_string_allocator: mem.Allocator) {
	context.allocator = p_string_allocator
	INTERNAL.string_table = make(map[Name]string)
}

//---------------------------------------------------------------------------//

make_name :: #force_inline proc(p_name: string) -> Name {
	return Name(hash.crc32(transmute([]u8)p_name))
}

//---------------------------------------------------------------------------//

create_name :: proc(p_name: string) -> Name {
	assert(len(p_name) > 0)
	name: Name
	name = Name(hash.crc32(transmute([]u8)p_name))
	if name in INTERNAL.string_table {
		return name
	}
	INTERNAL.string_table[name] = p_name
	return name
}

//---------------------------------------------------------------------------//


EMPTY_NAME := Name(0)

//---------------------------------------------------------------------------//

name_equal :: proc(p_name_1: Name, p_name_2: Name) -> bool {
	return p_name_1 == p_name_2
}

//---------------------------------------------------------------------------//

get_string :: proc(p_name: Name) -> string {
	when ODIN_DEBUG {
		assert(p_name in INTERNAL.string_table)
		return INTERNAL.string_table[p_name]
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

//---------------------------------------------------------------------------//

clone_string_array :: proc(p_strings: []string, p_allocator: mem.Allocator) -> []string {
	assert(len(p_strings) > 0)
	cloned := slice.clone(p_strings, p_allocator)
	for str, i in cloned {
		cloned[i] = strings.clone(str, p_allocator)
	}
	return cloned
}

//---------------------------------------------------------------------------//

aprintf :: proc(allocator: mem.Allocator, format: string, args: ..any) -> string {
	curr_alloc := context.allocator
	context.allocator = allocator
	defer context.allocator = curr_alloc
	return fmt.aprintf(format, ..args)
}

//---------------------------------------------------------------------------//
