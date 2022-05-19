package main

import "core:os"
import "../engine"

main :: proc() {
    engine_opts := engine.InitOptions {
        window_width = 1280,
        window_height = 720,
    }
    if engine.init(engine_opts) == false {
        os.exit(-1)
    } 
    engine.run()
}