
TODO:
- Create a black texture on the GPU that we'll use as the default 
- Check if the bindless descriptor set array is initialized to zeros
- backend_create_pipeline_layout for Vulkan doesn't support compute shaders
- Make sure render targets can be bound as Textures in the shader. Right now only the bindless texture array path is tested.
- Support loading volume DDS textures in the Vulkan backend, right now the asset pipeline supports them, but we ignore depth > 1
- When shaders.json is reloaded, we have to destroy the shaders that were loaded before

-> Add the bindless images descriptor set layout to the cache
-> Allow for empty fragment shader when loading material types (prepass)
-> Material types don't verify if a shader with a given path exists -> fix that
-> Create a separate pool for UPDATE_AFTER_BIND vulkan_renderer_resource_bind_group.odin
-> Buffer upload code dependes on num frames in flight - the number of staging regions is created based on 
    on that and never touched again after the initial setup. Same goes for async transfer sync primitives.