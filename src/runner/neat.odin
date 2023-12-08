package main

import "../common"
import "../engine"
import "../renderer"
import "core:math/linalg/glsl"
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

	mesh_asset_ref := engine.mesh_asset_load("FlightHelmet")
	mesh_asset := engine.mesh_asset_get(mesh_asset_ref)

	material_instance_ref := renderer.allocate_material_instance_ref(
		common.create_name("FlightHelmetMat"),
	)
	material_instance := &renderer.g_resources.material_instances[renderer.get_material_instance_idx(material_instance_ref)]
	material_instance.desc.material_type_ref = renderer.find_material_type("Default")
	renderer.create_material_instance(material_instance_ref)


	for i in 0 ..< 5 {
		for j in 0 ..< 5 {
			for k in 0 ..< 5 {
				mesh_instance_ref := renderer.allocate_mesh_instance_ref(
					common.create_name("FlightHelmet"),
				)
				mesh_instance := &renderer.g_resources.mesh_instances[renderer.get_mesh_instance_idx(mesh_instance_ref)]
				mesh_instance.desc.mesh_ref = mesh_asset.mesh_ref
				renderer.create_mesh_instance(mesh_instance_ref)
		
				mesh_instance.model_matrix *= glsl.mat4Translate(glsl.vec3{10.0 * f32(i), 10.0 * f32(j), 10.0 * f32(k)})
				mesh_instance.model_matrix *= glsl.mat4Scale({5, 5, 5})
			}
		}

	}

	engine.run()
}
