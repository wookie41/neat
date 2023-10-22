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

	// engine.texture_asset_import(engine.TextureAssertImportOptions {
	// 	file_path = "app_data/renderer/assets/textures/viking_room.png",
	// })

	engine.texture_asset_load_and_create_renderer_image("viking_room")
	engine.run()
}
