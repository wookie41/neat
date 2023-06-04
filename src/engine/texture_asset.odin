package engine

//---------------------------------------------------------------------------//

import "core:c/libc"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:encoding/json"
import "core:path/filepath"

//---------------------------------------------------------------------------//

@(private = "file")
TEXTURE_DB_PATH :: "app_data/renderer/assets/textures/db.json"

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

TextureImportResultStatus :: enum u16 {
	Ok,
	Duplicate,
	Error,
}

//---------------------------------------------------------------------------//

TextureImportResult :: struct {
	status: TextureImportResultStatus,
}

//---------------------------------------------------------------------------//

@(private = "file")
TextureDatabaseEntry :: struct {
	uuid:      UUID,
	name:      string, // User readable name of the texture
	file_name: string `json:"fileName"`, // Name of the texture file inside assets/textures dir
}

//---------------------------------------------------------------------------//

@(private = "file")
TEXTURE_DATABASE: struct {
	db_entries: [dynamic]TextureDatabaseEntry,
}

//---------------------------------------------------------------------------//

@(private)
texture_asset_init :: proc() {

	// Make sure that the texture database file is created
	if os.exists(TEXTURE_DB_PATH) == false {
		f, err := os.open(TEXTURE_DB_PATH, os.O_CREATE)
		assert(err == 0)
		_, err = os.write_string(f, "[]")
		assert(err == 0)
		os.close(f)
	}

	// Read the texture database
	db_data, db_read_ok := os.read_entire_file(TEXTURE_DB_PATH, G_ALLOCATORS.temp_allocator)
	assert(db_read_ok)

	err := json.unmarshal(
		db_data,
		&TEXTURE_DATABASE.db_entries,
		json.DEFAULT_SPECIFICATION,
		G_ALLOCATORS.main_allocator,
	)
	delete(db_data, G_ALLOCATORS.temp_allocator)
	assert(err == nil)
}
//---------------------------------------------------------------------------//

@(private = "file")
texture_asset_save_db :: proc() {
	json_data, err := json.marshal(
		TEXTURE_DATABASE.db_entries,
		json.Marshal_Options{spec = .JSON5, pretty = true},
		context.temp_allocator,
	)
	if err != nil {
		log.warnf("Failed marshall texture database: %s", err)
		return
	}
	defer delete(json_data, context.temp_allocator)
	if os.write_entire_file(TEXTURE_DB_PATH, json_data) == false {
		log.warnf("Failed to save texture database")
	}
}

//---------------------------------------------------------------------------//

texture_asset_import :: proc(p_options: TextureImportOptions) -> TextureImportResult {

	// Check if the texture already exits
	if os.exists(p_options.file_path) {
		return {status = .Duplicate}
	}

	// Pick compression format
	compression_format := "BC3_UNORM"
	if .IsNormalMap in p_options.flags {
		compression_format = "BC5_SNORM"
	} else if .IsGrayScale in p_options.flags {
		compression_format = "BC4_UNORM"
	} else if .IsCutout in p_options.flags {
		compression_format = "BC1_UNORM"
	} else if .IsHDR in p_options.flags {
		compression_format = "BC6H_UF16"
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
		return {status = .Error}
	}

	// Add an entry to the database
	file_name := filepath.short_stem(p_options.file_path)
	db_entry := TextureDatabaseEntry {
		uuid      = uuid_create(),
		file_name = strings.concatenate({file_name, ".dds"}, G_ALLOCATORS.main_allocator),
		name      = file_name,
	}
	append(&TEXTURE_DATABASE.db_entries, db_entry)

	// Save the database
	texture_asset_save_db()

	return {status = .Ok}
}

//---------------------------------------------------------------------------//
