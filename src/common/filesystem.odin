package common

import "core:time"
import "core:sys/windows"

//---------------------------------------------------------------------------//

get_last_file_write_time :: proc(p_file_path: string) -> time.Time {
    
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
        return time.Time{}
	}
	
    defer {
		windows.CloseHandle(file_handle)
	}

    ft_create: windows.FILETIME
    ft_access: windows.FILETIME
    ft_write: windows.FILETIME

    if !windows.GetFileTime(file_handle, &ft_create, &ft_access, &ft_write) {
        return time.Time{}
    }

    write_time : i64 = 0
    write_time |= i64(ft_write.dwLowDateTime)
    write_time |= (i64(ft_write.dwHighDateTime) << 32)

    return time.from_nanoseconds(write_time)
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