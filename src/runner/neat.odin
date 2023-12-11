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

	engine.mesh_asset_import(
		engine.MeshAssetImportOptions{
			file_path = "D:/glTF-Sample-Models-master/glTF-Sample-Models-master/2.0/Sponza/glTF/Sponza.gltf",
		},
	)

	mesh_asset_ref1 := engine.mesh_asset_load("FlightHelmet")
	mesh_asset_ref2 := engine.mesh_asset_load("SciFiHelmet")
	mesh_asset_ref3 := engine.mesh_asset_load("Sponza")

	mesh_asset1 := engine.mesh_asset_get(mesh_asset_ref1)
	mesh_asset2 := engine.mesh_asset_get(mesh_asset_ref2)
	mesh_asset3 := engine.mesh_asset_get(mesh_asset_ref3)

	mesh_assets := []^engine.MeshAsset{mesh_asset1, mesh_asset2, mesh_asset3}

	mesh_scales := []f32{20, 10, 0.025}

	for i in 0 ..< 5 {
		for j in 0 ..< 5 {
			for k in 0 ..< 5 {
				mesh_instance_ref := renderer.allocate_mesh_instance_ref(
					common.create_name("MeshInstance"),
				)
				mesh_instance := &renderer.g_resources.mesh_instances[renderer.get_mesh_instance_idx(mesh_instance_ref)]
				mesh_instance.desc.mesh_ref = mesh_assets[(i + j + k) % 3].mesh_ref
				renderer.create_mesh_instance(mesh_instance_ref)

				mesh_instance.model_matrix *= glsl.mat4Translate(
					glsl.vec3{f32(i) * 100.0, f32(j) * 100, f32(k) * 100} ,
				)

				mesh_scale := mesh_scales[(i + j + k) % 3]
				mesh_instance.model_matrix *= glsl.mat4Scale({mesh_scale, mesh_scale, mesh_scale})
			}
		}
	}

	engine.run()
}
