package main

import "../common"
import "../engine"
import "../renderer"
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

	engine.mesh_asset_load("FlightHelmet")

	material_instance_ref := renderer.allocate_material_instance_ref(
		common.create_name("FlightHelmetMat"),
	)
	material_instance := &renderer.g_resources.material_instances[renderer.get_material_instance_idx(material_instance_ref)]
	material_instance.desc.material_type_ref = renderer.find_material_type("Default")
	renderer.create_material_instance(material_instance_ref)

	mesh_instance_ref := renderer.allocate_mesh_instance_ref(common.create_name("FlightHelmet"))
	renderer.create_mesh_instance(mesh_instance_ref)

	engine.run()
}
