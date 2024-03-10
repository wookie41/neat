package common

//---------------------------------------------------------------------------//

import "core:container/bit_array"
import "core:encoding/json"
import "core:encoding/xml"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

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
	string_table:     map[Name]string,
	string_allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

init_names :: proc(p_string_allocator: mem.Allocator) {
	context.allocator = p_string_allocator
	INTERNAL.string_allocator = p_string_allocator
	INTERNAL.string_table = make(map[Name]string)
}

//---------------------------------------------------------------------------//

create_name :: proc(p_name: string) -> Name {
	assert(len(p_name) > 0)
	name := Name(hash.crc32(transmute([]u8)p_name))
	if name in INTERNAL.string_table {
		return name
	}
	INTERNAL.string_table[name] = strings.clone(p_name, INTERNAL.string_allocator)
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
	assert(p_name in INTERNAL.string_table)
	return INTERNAL.string_table[p_name]
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


bit_array_init :: proc(
	p_bit_array: ^bit_array.Bit_Array,
	max_index: int,
	min_index: int,
	allocator: mem.Allocator,
) -> bool {
	INDEX_SHIFT :: 6
	INDEX_MASK :: 63
	NUM_BITS :: 64

	context.allocator = allocator
	size_in_bits := max_index - min_index

	assert(size_in_bits > 0)
	legs := size_in_bits >> INDEX_SHIFT
	if size_in_bits & INDEX_MASK > 0 {legs += 1}
	bits, err := make([dynamic]u64, legs, allocator)
	if err != mem.Allocator_Error.None {
		return false
	}
	p_bit_array.bits = bits
	p_bit_array.bias = min_index
	p_bit_array.max_index = max_index
	p_bit_array.free_pointer = true

	return true
}

//---------------------------------------------------------------------------//

write_json_file :: proc(
	p_file_path: string,
	$T: typeid,
	p_value: T,
	p_allocator: mem.Allocator,
) -> bool {
	json_data, err := json.marshal(
		p_value,
		json.Marshal_Options{spec = .JSON5, pretty = true},
		p_allocator,
	)
	if err != nil {
		return false
	}
	defer delete(json_data, p_allocator)
	if os.write_entire_file(p_file_path, json_data) == false {
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

slice_cast :: proc($T: typeid, p_data: []byte, p_offset_in_bytes: u32, p_len: u32) -> []T {
	return slice.from_ptr(
		(^T)(mem.ptr_offset(raw_data(p_data), int(p_offset_in_bytes))),
		int(p_len),
	)
}

//---------------------------------------------------------------------------//

to_static_slice :: proc(p_src: [dynamic]$T, p_allocator: mem.Allocator) -> []T {
	static := make([]T, len(p_src), p_allocator)
	for v, i in p_src {
		static[i] = v
	}

	return static
}

//---------------------------------------------------------------------------//

xml_get_u32_attribute :: proc(
	p_doc: ^xml.Document,
	p_element_id: u32,
	p_attr_name: string,
) -> (
	u32,
	bool,
) {
	str, found := xml.find_attribute_val_by_key(p_doc, p_element_id, p_attr_name)
	if found == false {
		return 0, false
	}

	val, success := strconv.parse_uint(str, 10)
	if success == false {
		return 0, false
	}

	return u32(val), true
}

//---------------------------------------------------------------------------//

xml_get_u16_attribute :: proc(
	p_doc: ^xml.Document,
	p_element_id: u32,
	p_attr_name: string,
) -> (
	u16,
	bool,
) {
	str, found := xml.find_attribute_val_by_key(p_doc, p_element_id, p_attr_name)
	if found == false {
		return 0, false
	}

	val, success := strconv.parse_uint(str, 10)
	if success == false {
		return 0, false
	}

	return u16(val), true
}

//---------------------------------------------------------------------------//

// Converts slice into a dynamic array without cloning or allocating memory
@(require_results)
into_dynamic :: proc(a: $T/[]$E) -> [dynamic]E {
	s := transmute(runtime.Raw_Slice)a
	d := runtime.Raw_Dynamic_Array {
		data      = s.data,
		len       = s.len,
		cap       = s.len,
		allocator = runtime.nil_allocator(),
	}
	return transmute([dynamic]E)d
}

//---------------------------------------------------------------------------//

FileMemoryMapping :: struct {
	file_handle:    windows.HANDLE,
	mapping_handle: windows.HANDLE,
	mapped_ptr:     rawptr,
}

//---------------------------------------------------------------------------//

mmap_file :: proc(p_file_path: string) -> (out_mapping: FileMemoryMapping, out_res: bool) {

	temp_arena: Arena
	temp_arena_init(&temp_arena)
	defer arena_delete(temp_arena)

	path_w := windows.utf8_to_wstring(p_file_path, temp_arena.allocator)

	file_handle := windows.CreateFileW(
		path_w,
		windows.GENERIC_READ,
		windows.FILE_SHARE_READ,
		nil,
		windows.OPEN_EXISTING,
		windows.FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	if file_handle == windows.INVALID_HANDLE_VALUE {
		return {}, false
	}
	defer if (out_res == false) {
		windows.CloseHandle(file_handle)
	}

	mapping_handle := windows.CreateFileMappingW(
		file_handle,
		nil,
		windows.PAGE_READONLY,
		0,
		0,
		nil,
	)
	if mapping_handle == windows.INVALID_HANDLE_VALUE {
		return {}, false
	}

	file_mapped_ptr := windows.MapViewOfFile(mapping_handle, windows.FILE_MAP_READ, 0, 0, 0)

	return FileMemoryMapping{
			file_handle = file_handle,
			mapping_handle = mapping_handle,
			mapped_ptr = file_mapped_ptr,
		},
		true
}

//---------------------------------------------------------------------------//

unmap_file :: proc(p_mapping: FileMemoryMapping) {
	windows.UnmapViewOfFile(p_mapping.mapped_ptr)
	windows.CloseHandle(p_mapping.mapping_handle)
	windows.CloseHandle(p_mapping.file_handle)

}

//---------------------------------------------------------------------------//