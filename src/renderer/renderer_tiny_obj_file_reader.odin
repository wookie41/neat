package renderer

import "core:c"
import "core:os"
import "core:strings"
import "base:runtime"

@private
TinyObjLoaderContext :: struct {
    using ctx: runtime.Context,
}

create_new_tiny_obj_loader_ctx :: proc () -> TinyObjLoaderContext {
    return TinyObjLoaderContext {
        ctx = context,
    }
}

@private
g_tiny_obj_file_reader :: proc "c" (
	ctx: rawptr,
	filename: cstring,
	is_mtl: c.int,
	obj_filename: cstring,
	buf: ^cstring,
	out_len: ^c.size_t,
) {
    buf^ = nil

    loader_ctx := cast(^TinyObjLoaderContext)ctx
    context = loader_ctx.ctx
    
    file_path := string(filename)
    if is_mtl > 0 {
        file_path = strings.clone_from_cstring(filename)
    }
    defer if is_mtl > 0 {
        delete(file_path)
    }

    data, success := os.read_entire_file_from_filename(file_path)
    if success == false {
        return
    }

    out_len^ = c.size_t(len(data))
    buf^ = cast(cstring)raw_data(data)
}
