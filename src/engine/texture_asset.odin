package engine

//---------------------------------------------------------------------------//

import "core:c/libc"
import "core:fmt"
import "core:strings"
import "core:log"

//---------------------------------------------------------------------------//

TextureImportFlagBits :: enum u16 {
	IsHDR,
	IsNormalMap,
	IsGrayScale,
	IsCutout,
}

TextureImportFlags :: distinct bit_set[TextureImportFlagBits;u16]

//---------------------------------------------------------------------------//

TextureImportOptions :: struct {
	file_path: string,
	flags:     TextureImportFlags,
}

//---------------------------------------------------------------------------//

TextureImportResult :: struct {
	success: bool,
}

//---------------------------------------------------------------------------//

import_texture_asset :: proc(p_options: TextureImportOptions) -> TextureImportResult {

	// @TODO
	assert((.IsHDR in p_options.flags) == false)

	file_path := strings.clone_to_cstring(p_options.file_path, G_ALLOCATORS.temp_allocator)
	delete(file_path)

	compression_format := "BC3_UNORM"
	if .IsNormalMap in p_options.flags {
		compression_format = "BC5_SNORM"
	} else if .IsGrayScale in p_options.flags {
		compression_format = "BC4_UNORM"
	} else if .IsCutout in p_options.flags {
		compression_format = "BC1_UNORM"
	}

	// Convert the texture to dds 
	texconv_cmd := fmt.tprintf(
		"app_data\\renderer\\tools\\texconv.exe -f %s -o app_data/renderer/assets/textures %s",
		compression_format,
		p_options.file_path,
	)
	defer delete(texconv_cmd, context.temp_allocator)

	texconv_cmd_c := strings.clone_to_cstring(texconv_cmd, context.temp_allocator)
	defer delete(texconv_cmd_c)
	if res := libc.system(texconv_cmd_c); res != 0 {
		log.warnf("Failed to convert texture %s: %d", p_options.file_path, res)
		return {success = false}
	}
	
	return {success = true}
}

//---------------------------------------------------------------------------//
