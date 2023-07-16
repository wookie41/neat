package engine

//---------------------------------------------------------------------------//

import "core:strings"
import "core:log"
import "core:os"
import "core:mem"

import "../common"

//---------------------------------------------------------------------------//

AssetLoaderMode :: enum {
	Directory,
	Archive,
}

//---------------------------------------------------------------------------//

AssetLoaderInitOptions :: struct {
	mode: AssetLoaderMode,
}

AssetType :: enum {
	Texture,
	Mesh,
}

//---------------------------------------------------------------------------//


AssetLoadRequest :: struct {
	asset_name: common.Name,
	asset_type: AssetType,
}

//---------------------------------------------------------------------------//

AssetLoadResult :: struct {
	success: bool,
	data:    []byte,
}

//---------------------------------------------------------------------------//

@(private = "file")
AssetLoadFn :: distinct
proc(
	p_load_request: AssetLoadRequest,
	p_asset_data_allocator: mem.Allocator,
) -> AssetLoadResult

@(private = "file")
INTERNAL: struct {
	asset_load_function: AssetLoadFn,
}

//---------------------------------------------------------------------------//

asset_loader_init :: proc(p_options: AssetLoaderInitOptions) {
	if (p_options.mode == .Directory) {
		INTERNAL.asset_load_function = asset_load_from_directory
	} else {
		assert(false, "Not implemented")
	}
}

//---------------------------------------------------------------------------//

asset_loader_load :: proc(
	p_request: AssetLoadRequest,
	p_asset_data_allocator: mem.Allocator,
) -> AssetLoadResult {
	return INTERNAL.asset_load_function(p_request, p_asset_data_allocator)
}

//---------------------------------------------------------------------------//

@(private = "file")
asset_load_from_directory :: proc(
	p_load_request: AssetLoadRequest,
	p_asset_data_allocator: mem.Allocator,
) -> AssetLoadResult {

	temp_arena: TempArena
	temp_arena_init(&temp_arena)
	defer temp_arena_delete(temp_arena)

	asset_path := asset_loader_build_full_path(p_load_request, temp_arena.allocator)

	log.infof("Loading asset %s...", asset_path)
	asset_data, success := os.read_entire_file(asset_path, p_asset_data_allocator)

	return AssetLoadResult{data = asset_data, success = success}
}

//---------------------------------------------------------------------------//

asset_loader_build_full_path :: proc(
	p_load_request: AssetLoadRequest,
	p_allocator: mem.Allocator,
) -> string {
	asset_path_sb := strings.Builder{}
	strings.builder_init(&asset_path_sb, p_allocator)
	strings.write_string(&asset_path_sb, "app_data/engine/assets/")

	// Determine subdirectory based on asset type
	switch (p_load_request.asset_type) {
	case .Texture:
		strings.write_string(&asset_path_sb, "textures/")
	case .Mesh:
		strings.write_string(&asset_path_sb, "meshes/")
	case:
		assert(false, "Unsupported asset type")
	}

	strings.write_string(&asset_path_sb, common.get_string(p_load_request.asset_name))

    // Write extension
    switch (p_load_request.asset_type) {
        case .Texture:
            strings.write_string(&asset_path_sb, ".dds")
        case .Mesh:
            assert(false, "Unsupported asset type")
        case:
            assert(false, "Unsupported asset type")
        }
    
	return strings.to_string(asset_path_sb)
}
