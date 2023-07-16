package engine

//---------------------------------------------------------------------------//

import "../common"
import "../third_party/tinydds"

import "core:c"
import "core:c/libc"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:encoding/json"
import "core:path/filepath"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
G_TEXTURE_DB_PATH :: "app_data/engine/assets/textures/db.json"
@(private = "file")
G_TEXTURE_ASSETS_DIR :: "app_data/engine/assets/textures/"

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

@(private = "file")
INTERNAL: struct {
	tinydds_callbacks: tinydds.TinyDDS_Callbacks,
}


//---------------------------------------------------------------------------//

@(private = "file")
TinyDDSUserData :: struct {
	temp_arena:         ^TempArena,
	texture_asset_file: ^libc.FILE,
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_alloc :: proc(user: rawptr, size: c.size_t) -> rawptr {
	user_data := (^TinyDDSUserData)(user)
	return raw_data(make([]byte, size, user_data.temp_arena.allocator))
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_free :: proc(user: rawptr, memory: rawptr) {
	// We user an arena when loading the dds that is freed at the end of the call
	// So no need to free memory here
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_read :: proc(user: rawptr, buffer: rawptr, byte_count: c.size_t) -> c.size_t {
	user_data := (^TinyDDSUserData)(user)
	return libc.fread(buffer, byte_count, 1, user_data.texture_asset_file) * byte_count
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_seek :: proc(user: rawptr, offset: i64) -> bool {
	user_data := (^TinyDDSUserData)(user)
	return libc.fseek(user_data.texture_asset_file, i32(offset), os.SEEK_SET) == 0
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_tell :: proc(user: rawptr) -> i64 {
	user_data := (^TinyDDSUserData)(user)
	return i64(libc.ftell(user_data.texture_asset_file))
}

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_error :: proc(user: rawptr, msg: cstring) {
	log.errorf("TinyDDS error: %s\n", string(msg))
}
//---------------------------------------------------------------------------//

TextureAssetType :: enum {
	_1D,
	_2D,
	_3D,
}

//---------------------------------------------------------------------------//

TextureData :: struct {
	data_per_mip: [][]byte,
}

//---------------------------------------------------------------------------//

TextureFormat :: enum {
	BC1_Unorm,
	BC3_UNorm,
	BC4_UNorm,
	BC5_UNorm,
	BC6H_UFloat16,
}

//---------------------------------------------------------------------------//

TextureAsset :: struct {
	name:          common.Name,
	num_mips:      u8,
	width:         u16,
	height:        u16,
	depth:         u16,
	texture_datas: []TextureData,
	format:        TextureFormat,
}

//---------------------------------------------------------------------------//

@(private)
texture_asset_init :: proc() {

	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	// Make sure that the texture database file is created
	if os.exists(G_TEXTURE_DB_PATH) == false {
		f, err := os.open(G_TEXTURE_DB_PATH, os.O_CREATE)
		assert(err == 0)
		_, err = os.write_string(f, "[]")
		assert(err == 0)
		os.close(f)
	}

	// Read the texture database
	db_data, db_read_ok := os.read_entire_file(G_TEXTURE_DB_PATH, temp_arena.allocator)
	assert(db_read_ok)

	err := json.unmarshal(
		db_data,
		&TEXTURE_DATABASE.db_entries,
		json.DEFAULT_SPECIFICATION,
		G_ALLOCATORS.main_allocator,
	)
	assert(err == nil)

	// Setup tiny dds callbacks
	INTERNAL.tinydds_callbacks = {
		allocFn = tinydds_alloc,
		freeFn  = tinydds_free,
		readFn  = tinydds_read,
		seekFn  = tinydds_seek,
		tellFn  = tinydds_tell,
		errorFn = tinydds_error,
	}
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
	if os.write_entire_file(G_TEXTURE_DB_PATH, json_data) == false {
		log.warnf("Failed to save texture database")
	}
}

//---------------------------------------------------------------------------//

texture_asset_import :: proc(p_options: TextureImportOptions) -> TextureImportResult {

	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	// Check if the texture already exits
	texture_name := filepath.short_stem(p_options.file_path)
	texture_file_name := strings.concatenate({texture_name, ".dds"}, temp_arena.allocator)
	texture_file_path := strings.concatenate(
		{G_TEXTURE_ASSETS_DIR, texture_file_name},
		temp_arena.allocator,
	)

	if os.exists(texture_file_path) {
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
		"app_data\\engine\\tools\\texconv.exe -pow2 -o %s -f %s %s ",
		G_TEXTURE_ASSETS_DIR,
		compression_format,
		p_options.file_path,
	)

	texconv_cmd_c := strings.clone_to_cstring(texconv_cmd, temp_arena.allocator)
	if res := libc.system(texconv_cmd_c); res != 0 {
		log.warnf("Failed to convert texture %s: %d", p_options.file_path, res)
		return {status = .Error}
	}

	// Add an entry to the database
	db_entry := TextureDatabaseEntry {
		uuid      = uuid_create(),
		name      = texture_name,
		file_name = texture_file_name,
	}
	append(&TEXTURE_DATABASE.db_entries, db_entry)

	// Save the database
	texture_asset_save_db()

	return {status = .Ok}
}

//---------------------------------------------------------------------------//

texture_asset_load :: proc(
	p_texture_name: common.Name,
	p_texture_data_allocator: mem.Allocator,
) -> TextureAssetRef {

	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	asset_path := asset_loader_build_full_path(
		AssetLoadRequest{asset_name = p_texture_name, asset_type = .Texture},
		temp_arena.allocator,
	)

	asset_path_c := strings.clone_to_cstring(asset_path, temp_arena.allocator)
	texture_asset_file := libc.fopen(asset_path_c, "r")
	if texture_asset_file == nil {
		log.errorf("Failed open texture asset file: %s\n", asset_path)
		return AssetLoadResult{success = false}
	}
	defer libc.fclose(texture_asset_file)

	// Init tiny dds
	user_data := TinyDDSUserData {
		temp_arena         = &temp_arena,
		texture_asset_file = texture_asset_file,
	}

	// Load texture information
	texture_asset: TextureAsset

	tinydds_ctx := tinydds.create_context(&INTERNAL.tinydds_callbacks, &user_data)
	defer tinydds.destroy_context(tinydds_ctx)
	if tinydds.read_header(tinydds_ctx) == false {
		log.warnf(
			"Failed to read the DDS header for texture %s\n",
			common.get_string(p_texture_name),
		)
		return AssetLoadResult{success = false}
	}

	texture_asset.num_mips = tinydds.number_of_mipmaps(tinydds_ctx)
	&texture_asset.width = tinydds.width(tinydds_ctx)
	&texture_asset.height = tinydds.height()(tinydds_ctx)
	&texture_asset.depth = tinydds.depth(tinydds_ctx)

	tinydds_format := tinydds.get_format(tinydds_ctx)

	switch tinydds_format {
	case .TddsBc1RgbaUnormBlock:
		texture_asset.format = .BC1_Unorm
	case .TddsBc3R:
		texture_asset.format = .BC3_Unorm
	case .TddsBc4RgbaUnormBlock:
		texture_asset.format = .BC4_Unorm
	case .TddsBc5RgbaUnormBlock:
		texture_asset.format = .BC5_Unorm
	case .TddsBc6HUfloatBlock:
		texture_asset.format = .BC6H_UFloat
	}

	// Get the texture data
	texture_asset.texture_datas = make(
		[]TextureData,
		texture_asset.depth,
		p_texture_data_allocator,
	)
	for i in 0 ..< texture_asset.depth {
		texture_asset.texture_datas[i].data_per_mip = make(
			[][]byte,
			texture_asset.num_mips,
			p_texture_data_allocator,
		)
		for j in 0 ..< texture_asset.num_mips {
			texture_asset.texture_datas[i].data_per_mip[j] = tinydds.image_raw_data(j)
		}
	}

	return AssetLoadResult{success = true}
}

//---------------------------------------------------------------------------//
