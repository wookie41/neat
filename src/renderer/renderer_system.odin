package renderer

//---------------------------------------------------------------------------//

import "core:mem"
import "core:log"

//---------------------------------------------------------------------------//

@(private)
USE_VULKAN_BACKEND :: #config(USE_VULKAN_BACKEND, true)

@(private)
MAX_NUM_FRAMES_IN_FLIGHT :: #config(NUM_FRAMES_IN_FLIGHT, 2)

//---------------------------------------------------------------------------//

@(private)
G_RENDERER : struct {
    using backend_state: BackendRendererState,

    allocator: mem.Allocator,
    
    temp_arena: mem.Arena,    
    temp_arena_allocator: mem.Allocator,
}

@(private)
G_RENDERER_LOG: log.Logger

//---------------------------------------------------------------------------//

InitOptions :: struct {
    using backend_options: BackendInitOptions,
    allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

init :: proc(p_options: InitOptions) -> bool {
    G_RENDERER_LOG = log.create_console_logger()
    
    backend_init(p_options) or_return
    init_vt()
    return true    
}
//---------------------------------------------------------------------------//

update :: proc(p_dt: f32) {
    backend_update(p_dt)
}

//---------------------------------------------------------------------------//

deinit :: proc() {
    backend_deinit()
}