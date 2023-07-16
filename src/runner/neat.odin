package main

import "core:os"
import "../engine"
import "../common"

main :: proc() {
	engine_opts := engine.InitOptions {
		window_width  = 1280,
		window_height = 720,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}

	// engine.texture_asset_import(engine.TextureImportOptions {
	// 	file_path = "app_data/renderer/assets/textures/viking_room.png",
	// })

	image_name := common.create_name("viking_room")
	texture_load_result := engine.texture_asset_load(image_name, context.allocator)
	defer if texture_load_result.success == false {
		delete(texture_load_result.data, context.allocator)
	}

	// image_ref := renderer.allocate_image_ref(common.create_name("VikingRoom"))
	// image := renderer.get_image(image_ref)
	//engine.run()
}
