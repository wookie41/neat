package common

import _hash "core:hash"

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

create_name :: proc(p_name: string) -> Name {
	when ODIN_DEBUG {
		return Name{hash = _hash.crc32(transmute([]u8)p_name), name = p_name}
	} else {
		return Name{hash = _hash.crc32(transmute([]u8)p_name)}
	}
}

//---------------------------------------------------------------------------//

when ODIN_DEBUG {
	destroy_name :: #force_inline proc(p_name: Name) {
		delete(p_name.name)
	}
} else {
	destroy_name :: #force_inline proc(p_name: Name) {
	}	
}


//---------------------------------------------------------------------------//

EMPTY_NAME := create_name("")

//---------------------------------------------------------------------------//


name_equal :: proc {
	name_equal_str,
	name_equal_hash,
	name_equal_name,
}

//---------------------------------------------------------------------------//

name_equal_str :: proc(p_name: Name, p_str: string) -> bool {
	return p_name.hash == _hash.crc32(transmute([]u8)p_str)
}

//---------------------------------------------------------------------------//

name_equal_name :: proc(p_name_1: Name, p_name_2: Name) -> bool {
	return p_name_1.hash == p_name_2.hash
}

//---------------------------------------------------------------------------//

name_equal_hash :: proc(p_name_1: u32, p_name_2: Name) -> bool {
	return p_name_1 == p_name_2.hash
}

//---------------------------------------------------------------------------//

when ODIN_DEBUG {
	Name :: struct {
		hash: u32,
		name: string,
	}

	get_name :: proc(p_name: Name) -> string {
		return p_name.name
	}

} else {
	Name :: struct {
		hash: u32,
	}

	get_name :: proc(p_name: Name) -> u32 {
		return p_name.hash
	}
}
//---------------------------------------------------------------------------//
