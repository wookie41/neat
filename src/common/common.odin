package common

import _hash "core:hash"

//---------------------------------------------------------------------------//

KILOBYTE :: 1024
MEGABYTE :: KILOBYTE * 1024
GIGABYTE :: MEGABYTE * 1024

//---------------------------------------------------------------------------//

make_name :: proc(p_name: string) -> Name {
    when ODIN_DEBUG {
        return Name {
            hash= _hash.crc32(transmute([]u8)p_name),
            name= p_name,
        }
    } else {
        return Name {
            hash = _hash.crc32(transmute([]u8)p_name),
        }
    }
}

//---------------------------------------------------------------------------//

name_equal :: proc(p_name: Name, p_str: string) -> bool {
    return p_name.hash == _hash.crc32(transmute([]u8)p_str)
}

//---------------------------------------------------------------------------//

when ODIN_DEBUG {
	Name :: struct {
		hash: u32,
		name: string,
	}
} else {
	Name :: struct {
		hash: u32,
	}
}
//---------------------------------------------------------------------------//
