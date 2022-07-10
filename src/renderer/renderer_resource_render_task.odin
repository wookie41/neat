package renderer

import "../common"

//---------------------------------------------------------------------------//

RenderTask :: struct {
    name: common.Name,
    init: proc(),
    run: proc(dt: f32),
    deinit: proc(),
}

//---------------------------------------------------------------------------//