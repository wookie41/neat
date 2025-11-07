package main

import "../common"
import "../engine"
import "../renderer"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"

main :: proc() {

	logg := log.create_console_logger()
	context.logger = logg

	engine_opts := engine.InitOptions {
		window_width  = 1920,
		window_height = 1080,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions {
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/FlightHelmet/glTF/FlightHelmet.gltf",
		},
	)

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions {
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/SciFiHelmet/glTF/SciFiHelmet.gltf",
		},
	)

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions {
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/Sponza/glTF/Sponza.gltf",
		},
	)

	// flight_helmet := engine.mesh_asset_get(engine.mesh_asset_load("FlightHelmet"))
	// scifi_helmet := engine.mesh_asset_get(engine.mesh_asset_load("SciFiHelmet"))
	sponza := engine.mesh_asset_get(engine.mesh_asset_load("Sponza"))

	// Spawn Sponza
	renderer.mesh_instance_spawn(
		common.create_name("Sponza"),
		sponza.mesh_ref,
		glsl.vec3(0),
	)
	
	// Spawn a few flight helmets
	// for i in 0 ..< 5 {
	// 	renderer.mesh_instance_spawn(
	// 		common.create_name("FlightHelmet"),
	// 		flight_helmet.mesh_ref,
	// 		glsl.vec3{f32(2 * i), 2, 0},
	// 	)
	// }
	
	// // Spawn a few scifi helmets
	// for i in 0 ..< 5 {
	// 	renderer.mesh_instance_spawn(
	// 		common.create_name("SciFiHelmet"),
	// 		scifi_helmet.mesh_ref,
	// 		glsl.vec3{f32(2 * i) - 10, 2, 0},
	// 		glsl.vec3(0.15),
	// 	)
	// }

	engine.run()
}
