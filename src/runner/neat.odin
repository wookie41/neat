package main

import "core:os"
import "../engine"

main :: proc() {
	engine_opts := engine.InitOptions {
		window_width  = 1280,
		window_height = 720,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}

	engine.texture_asset_import(engine.TextureAssetImportOptions {
		file_path = "app_data/renderer/assets/textures/viking_room.png",
	})

	engine.mesh_asset_import(engine.MeshAssetImportOptions {
		file_path = "app_data/renderer/assets/models/viking_room.obj",
	})

	engine.texture_asset_load("viking_room")
	engine.run()
}
