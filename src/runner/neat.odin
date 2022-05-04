package main

import "../engine"

main :: proc() {
    engine_opts := engine.InitOptions {
        window_width = 1280,
        window_height = 720,
    }
    engine.init(engine_opts)
    engine.run()
}