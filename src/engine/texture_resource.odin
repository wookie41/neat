package engine

//---------------------------------------------------------------------------//

import "core:c"
import "core:strings"
import stb_image "vendor:stb/image"

//---------------------------------------------------------------------------//

TextureImportFlagBits :: enum u16 {
    IsHDR,
}

TextureImportFlags :: distinct bit_set[TextureImportFlagBits;u16]

//---------------------------------------------------------------------------//

TextureImportOptions :: struct {
    file_path: string,
    flags: TextureImportFlags,
}

//---------------------------------------------------------------------------//

TextureImportResult :: struct {
    success: bool,
}

//---------------------------------------------------------------------------//

import_texture :: proc(p_options: TextureImportOptions) -> TextureImportResult {

    // @TODO
    assert((.IsHDR in p_options.flags) == false)

    file_path := strings.clone_to_cstring(p_options.file_path, G_ALLOCATORS.temp_allocator)
    delete(file_path)

	image_width, image_height, channels: c.int
    pixels := stb_image.load(
		file_path,
		&image_width,
		&image_height,
		&channels,
		4,
	)

}

//---------------------------------------------------------------------------//