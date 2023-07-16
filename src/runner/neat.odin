package main

import "core:os"
import "../engine"
import "../common"
import "../renderer"
import "core:math/linalg/glsl"

main :: proc() {
	engine_opts := engine.InitOptions {
		window_width  = 1280,
		window_height = 720,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}

	engine.texture_asset_import(engine.TextureImportOptions {
		file_path = "app_data/renderer/assets/textures/viking_room.png",
	})

	image_name := common.create_name("viking_room")
	texture_asset_ref := engine.texture_asset_load(image_name)
	texture_asset := engine.get_texture_asset(texture_asset_ref)

	image_ref := renderer.allocate_image_ref(common.create_name("VikingRoom"))
	image := renderer.get_image(image_ref)
	image.desc.format = .BC3_UNorm
	image.desc.type = .TwoDimensional
	image.desc.mip_count = texture_asset.num_mips
	image.desc.data_per_mip = texture_asset.texture_datas[0].data_per_mip
	image.desc.dimensions = glsl.uvec3{texture_asset.width, texture_asset.height, 1}
	image.desc.sample_count_flags = {._1}

	assert(renderer.create_texture_image(image_ref))

	engine.run()
}
