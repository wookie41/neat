package engine

//---------------------------------------------------------------------------//

// import "../common"

//---------------------------------------------------------------------------//

MeshAssetImportFlagBits :: enum u16 {}

MeshAssetImportFlags :: distinct bit_set[MeshAssetImportFlagBits;u16]

//---------------------------------------------------------------------------//

MeshAssetImportOptions :: struct {
	file_path: string,
	flags:     MeshAssetImportFlags,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshAssetMetadata :: struct {
	uuid:    UUID,
	version: uint, // Metadata file version
}

//---------------------------------------------------------------------------//

// mesh_asset_import :: proc(p_import_options: ^MeshAssetImportOptions) -> AssetImportResult {

// 	temp_arena: common.TempArena
// 	common.temp_arena_init(&temp_arena)
// 	defer common.temp_arena_delete(temp_arena)
// }

//---------------------------------------------------------------------------//
