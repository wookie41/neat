package engine

//---------------------------------------------------------------------------//

import "../common"
import "../third_party/tinydds"
import "../renderer"

import "core:c"
import "core:mem"
import "core:slice"
import "core:c/libc"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:encoding/json"
import "core:path/filepath"
import "core:math/linalg/glsl"

//---------------------------------------------------------------------------//

G_METADATA_FILE_VERSION :: 1

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
TextureMetadata :: struct {
	uuid:    UUID,
	version: uint, // Metadata file version
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
	return raw_data(make([]byte, size, G_ALLOCATORS.asset_allocator))
}

//---------------------------------------------------------------------------//

tinydds_alloc_temp :: proc(user: rawptr, size: c.size_t) -> rawptr {
	user_data := (^TinyDDSUserData)(user)
	return raw_data(make([]byte, size, user_data.temp_arena.allocator))
}


//---------------------------------------------------------------------------//

@(private = "file")
tinydds_free :: proc(user: rawptr, memory: rawptr) {
	// We're not resetting the tinydds context, instead we manually free the texture data explcilty
	// so we don't care about this call
}
//---------------------------------------------------------------------------//

@(private = "file")
tinydds_free_temp :: proc(user: rawptr, memory: rawptr) {
	// We use an arena when loading the dds that is freed at the end of the call
	// So no need to free memory here
}


//---------------------------------------------------------------------------//

@(private = "file")
tinydds_read :: proc(user: rawptr, buffer: rawptr, byte_count: c.size_t) -> c.size_t {
	user_data := (^TinyDDSUserData)(user)
	return libc.fread(
		buffer, 
		byte_count,
		1,
		user_data.texture_asset_file) * byte_count
}		

//---------------------------------------------------------------------------//

@(private = "file")
tinydds_seek :: proc(user: rawptr, offset: i64) -> bool {
	user_data := (^TinyDDSUserData)(user)
	return libc.fseek(user_data.texture_asset_file, i32(offset), 0) == 0
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
	fmt.printf("TinyDDS error: %s\n", string(msg))
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

TextureAssetRef :: common.Ref(TextureAsset)

//---------------------------------------------------------------------------//

InvalidTextureAssetRef := TextureAssetRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

MAX_TEXTURE_ASSETS :: 1024

//---------------------------------------------------------------------------//

@(private = "file")
G_TEXTURE_ASSET_REF_ARRAY: common.RefArray(TextureAsset)
@(private = "file")
G_TEXTURE_ASSET_ARRAY: []TextureAsset

//---------------------------------------------------------------------------//

TextureAsset :: struct {
	using asset:   AssetBase,
	num_mips:      u8,
	width:         u32,
	height:        u32,
	depth:         u32,
	texture_datas: []TextureData,
	format:        TextureFormat,
}

//---------------------------------------------------------------------------//

allocate_texture_asset_ref :: proc(p_name: common.Name) -> TextureAssetRef {
	ref := TextureAssetRef(common.ref_create(TextureAsset, &G_TEXTURE_ASSET_REF_ARRAY, p_name))
	texture := get_texture_asset(ref)
	texture.name = p_name
	texture.type = .Texture
	return ref
}

//---------------------------------------------------------------------------//

get_texture_asset :: proc(p_ref: TextureAssetRef) -> ^TextureAsset {
	return &G_TEXTURE_ASSET_ARRAY[common.ref_get_idx(&G_TEXTURE_ASSET_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

@(private)
texture_asset_init :: proc() {

	G_TEXTURE_ASSET_REF_ARRAY = common.ref_array_create(
		TextureAsset,
		MAX_TEXTURE_ASSETS,
		G_ALLOCATORS.asset_allocator,
	)
	G_TEXTURE_ASSET_ARRAY = make([]TextureAsset, MAX_TEXTURE_ASSETS, G_ALLOCATORS.asset_allocator)

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
		allocTempFn = tinydds_alloc_temp,
		freeFn  = tinydds_free,
		freeTempFn  = tinydds_free_temp,
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


	texture_uuid := uuid_create()
	// Write the metadata file
	{
		texture_metadata := TextureMetadata {
			uuid    = texture_uuid,
			version = G_METADATA_FILE_VERSION,
		}
		json_data, err := json.marshal(
			texture_metadata,
			json.Marshal_Options{spec = .JSON5, pretty = true},
			temp_arena.allocator,
		)
		if err != nil {
			log.warnf("Failed to import texture '%s' - couldn't prepare metadata\n", texture_name)
			return {status = .Error}
		}
		if os.write_entire_file(
			   common.aprintf(temp_arena.allocator, "%s%s.metadata", G_TEXTURE_ASSETS_DIR, texture_name),
			   json_data,
		   ) ==
		   false {
			log.warnf("Failed to import texture '%s' - couldn't save metadata\n", texture_name)
			return {status = .Error}
		}
	}

	// Pick compression format
	// https://learn.microsoft.com/en-us/windows/win32/direct3d11/texture-block-compression-in-direct3d-11#block-compression-formats-supported-in-direct3d-11
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
		uuid      = texture_uuid,
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
	p_texture_name: common.Name
) -> TextureAssetRef {

	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	// Open the texture metadata file


	// Open the texture file
	asset_path := asset_loader_build_full_path(
		AssetLoadRequest{asset_name = p_texture_name, asset_type = .Texture},
		temp_arena.allocator,
	)

	asset_path_c := strings.clone_to_cstring(asset_path, temp_arena.allocator)
	texture_asset_file := libc.fopen(asset_path_c, "rb")
	if texture_asset_file == nil {
		log.errorf("Failed open texture asset file: %s\n", asset_path)
		return InvalidTextureAssetRef
	}
	defer libc.fclose(texture_asset_file)

	// Init tiny dds
	user_data := TinyDDSUserData {
		temp_arena         = &temp_arena,
		texture_asset_file = texture_asset_file,
	}

	texture_metadata : TextureMetadata
	texture_name := common.get_string(p_texture_name)

	// Load texture metadata
	{
		texture_metadata_file_path := common.aprintf(temp_arena.allocator, "%s%s.metadata", G_TEXTURE_ASSETS_DIR, texture_name)
		texture_metadata_json, success := os.read_entire_file(texture_metadata_file_path, temp_arena.allocator)
		if !success {
			log.warnf("Failed to load texture '%s' - couldn't load metadata\n", texture_name)
			return InvalidTextureAssetRef
		}
		err := json.unmarshal(texture_metadata_json, &texture_metadata, .JSON5, temp_arena.allocator)
		if err != nil {
			log.warnf("Failed to load texture '%s' - couldn't read metadata\n", texture_name)
			return InvalidTextureAssetRef
		}
	}

	texture_ref := allocate_texture_asset_ref(p_texture_name)
	texture_asset := get_texture_asset(texture_ref)
	texture_asset.uuid = texture_metadata.uuid

	tinydds_ctx := tinydds.create_context(&INTERNAL.tinydds_callbacks, &user_data)
	defer tinydds.destroy_context(tinydds_ctx)
	if tinydds.read_header(tinydds_ctx) == false {
		log.warnf(
			"Failed to read the DDS header for texture %s\n",
			common.get_string(p_texture_name),
		)
		return InvalidTextureAssetRef
	}

	texture_asset.num_mips = u8(tinydds.number_of_mipmaps(tinydds_ctx))
	texture_asset.width = tinydds.width(tinydds_ctx)
	texture_asset.height = tinydds.height(tinydds_ctx)
	texture_asset.depth = tinydds.depth(tinydds_ctx)

	tinydds_format := tinydds.get_format(tinydds_ctx)

	#partial switch tinydds_format {
	case .TddsBc1RgbaUnormBlock:
		texture_asset.format = .BC1_Unorm
	case .TddsBc3UnormBlock:
		texture_asset.format = .BC3_UNorm
	case .TddsBc4UnormBlock:
		texture_asset.format = .BC4_UNorm
	case .TddsBc5UnormBlock:
		texture_asset.format = .BC5_UNorm
	case .TddsBc6HUfloatBlock:
		texture_asset.format = .BC6H_UFloat16
		case:
			assert(false, "Unsupported texture format")
	}

	// Get the texture data
	if  !texture_asset_load_texture_data_tiny_dds(tinydds_ctx, texture_asset, temp_arena.allocator) {
		common.ref_free(&G_TEXTURE_ASSET_REF_ARRAY, texture_ref)
		return InvalidTextureAssetRef
	}


	log.infof("Texture '%s' loaded successfully\n", texture_name)
	return texture_ref
}

//---------------------------------------------------------------------------//

texture_asset_unload :: proc(p_texture_asset_ref: TextureAssetRef) {
	texture_asset := get_texture_asset(p_texture_asset_ref)
	for i in 0 ..< texture_asset.depth {
		for j in 0 ..< u32(texture_asset.num_mips) {
			delete(texture_asset.texture_datas[i].data_per_mip[j], G_ALLOCATORS.main_allocator)
		}
		delete(texture_asset.texture_datas[i].data_per_mip, G_ALLOCATORS.main_allocator)
	}
	delete(texture_asset.texture_datas, G_ALLOCATORS.main_allocator)
	common.ref_free(&G_TEXTURE_ASSET_REF_ARRAY, p_texture_asset_ref)
}

//---------------------------------------------------------------------------//

@(private="file")
texture_asset_load_texture_data_tiny_dds :: proc(
	p_tinydds_ctx: tinydds.TinyDDS_ContextHandle, 
	p_texture_asset: ^TextureAsset, 
	p_allocator: mem.Allocator) -> bool {

	// For easier cleanup on failure
	loaded_mips := make([dynamic][]byte, p_allocator)

	p_texture_asset.texture_datas = make(
		[]TextureData,
		int(p_texture_asset.depth),
		G_ALLOCATORS.asset_allocator,
	)

	// Load each depth
	for i in 0 ..< p_texture_asset.depth {
		p_texture_asset.texture_datas[i].data_per_mip = make(
			[][]byte,
			int(p_texture_asset.num_mips),
			G_ALLOCATORS.asset_allocator,
		)
		// Load each mip
		for j in 0 ..< u32(p_texture_asset.num_mips) {
			image_data := tinydds.image_raw_data(p_tinydds_ctx, i, j)

			// Cleanup on failure
			if image_data == nil {
				for k in 0 ..= i {
					delete(p_texture_asset.texture_datas[i].data_per_mip, G_ALLOCATORS.asset_allocator)
				}
				delete(p_texture_asset.texture_datas, G_ALLOCATORS.asset_allocator)
				for mip_data in loaded_mips {
					delete(mip_data, G_ALLOCATORS.asset_allocator)
				}
				return false
			}

			// Get the data
			p_texture_asset.texture_datas[i].data_per_mip[j] = slice.bytes_from_ptr(
				image_data,
				int(tinydds.face_size(p_tinydds_ctx, j)),
			)
			append(&loaded_mips, p_texture_asset.texture_datas[i].data_per_mip[j])
		}
	}
	return true
}

//---------------------------------------------------------------------------//

texture_asset_load_and_create_renderer_image_string :: proc (p_name: string) -> (TextureAssetRef, renderer.ImageRef) {
	return texture_asset_load_and_create_renderer_image_name(common.create_name(p_name))
}

texture_asset_load_and_create_renderer_image_name :: proc (p_name: common.Name) -> (TextureAssetRef, renderer.ImageRef) {
	log.info("Loading texture '%s'...\n", common.get_string(p_name))
	texture_asset_ref := texture_asset_load(p_name)
	if texture_asset_ref == InvalidTextureAssetRef {
		return InvalidTextureAssetRef, renderer.InvalidImageRef
	}
	texture_asset := get_texture_asset(texture_asset_ref)

	image_ref := renderer.allocate_image_ref(p_name)
	image := renderer.get_image(image_ref)

	if image_ref == renderer.InvalidImageRef {
		texture_asset_unload(texture_asset_ref)
		return InvalidTextureAssetRef, renderer.InvalidImageRef
	}

	#partial switch texture_asset.format {
		case .BC1_Unorm:
			image.desc.format = .BC1_RGBA_UNorm
		case .BC3_UNorm:
			image.desc.format = .BC3_UNorm
		case .BC4_UNorm:
			image.desc.format = .BC4_UNorm
		case .BC5_UNorm:
			image.desc.format = .BC5_UNorm
		case .BC6H_UFloat16	:
			image.desc.format = .BC6H_UFloat
		case:
			texture_asset_unload(texture_asset_ref)
			renderer.destroy_image(image_ref)
			log.warnf("Unsupported image format for image '%s'\n", common.get_string(p_name))
			return InvalidTextureAssetRef, renderer.InvalidImageRef	
	}

	image.desc.type = .TwoDimensional
	image.desc.mip_count = texture_asset.num_mips
	// @TODO support for more slices
	image.desc.data_per_mip = texture_asset.texture_datas[0].data_per_mip
	image.desc.dimensions = glsl.uvec3{texture_asset.width, texture_asset.height, 1}
	image.desc.sample_count_flags = {._1}

	if renderer.create_texture_image(image_ref) == false {
		texture_asset_unload(texture_asset_ref)
		return InvalidTextureAssetRef, renderer.InvalidImageRef
	}

	return texture_asset_ref, image_ref
}

texture_asset_load_and_create_renderer_image :: proc {
	texture_asset_load_and_create_renderer_image_string,
	texture_asset_load_and_create_renderer_image_name,
}

//---------------------------------------------------------------------------//