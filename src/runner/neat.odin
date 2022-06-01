package main

import "core:os"
import "../engine"
import "../renderer"
import "../common"
import "core:fmt"
main :: proc() {
	shader_ref_array := renderer.create_ref_array(.SHADER, 32)
    shader_name := common.create_name("test")
	ref := renderer.create_ref(&shader_ref_array, shader_name)
	ref2 := renderer.create_ref(&shader_ref_array, shader_name)
	fmt.printf(
		"Idx: %d, type: %d, gen: %d\n",
		renderer.get_ref_idx(ref),
		renderer.get_ref_res_type(ref),
		renderer.get_ref_generation(ref),
	)
    fmt.printf(
		"Idx: %d, type: %d, gen: %d\n",
		renderer.get_ref_idx(ref2),
		renderer.get_ref_res_type(ref2),
		renderer.get_ref_generation(ref2),
	)
    renderer.free_ref(&shader_ref_array, ref)
	ref3 := renderer.create_ref(&shader_ref_array, shader_name)
    fmt.printf(
		"Idx: %d, type: %d, gen: %d\n",
		renderer.get_ref_idx(ref3),
		renderer.get_ref_res_type(ref3),
		renderer.get_ref_generation(ref3),
	)

	engine_opts := engine.InitOptions {
		window_width  = 1280,
		window_height = 720,
	}
	if engine.init(engine_opts) == false {
		os.exit(-1)
	}
	engine.run()

}
