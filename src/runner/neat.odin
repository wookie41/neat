package main

import "../engine"
import "core:os"

main :: proc() {
	engine_opts := engine.InitOptions {
		window_width  = 1280,
		window_height = 720,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions{
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/FlightHelmet/glTF/FlightHelmet.gltf",
		},
	)

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions{
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/SciFiHelmet/glTF/SciFiHelmet.gltf",
		},
	)

	engine.texture_asset_load("viking_room")
	engine.mesh_asset_load("FlightHelmet")
	engine.run()
}
