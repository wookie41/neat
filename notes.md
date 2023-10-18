
TODO:
- Create a black texture on the GPU that we'll use as the default 
- Check if the bindless descriptor set array is initialized to zeros
- backend_create_pipeline_layout for Vulkan doesn't support compute shaders
- Make sure render targets can be bound as Textures in the shader. Right now only the bindless texture array path is tested.
- Create a cache for descriptor set layouts and resuse them (vulkan_renderer_resource_pipeline_layout.odin)
- Support loading volume DDS textures in the Vulkan backend, right now the asset pipeline supports them, but we ignore depth > 1
- When shaders.json is reloaded, we have to destroy the shaders that were loaded before

-> Add the bindless images descriptor set layout to the cache
-> Test material system implementation
-> Allow for empty fragment shader when loading material types (prepass)
-> Material types don't verify if a shader with a given path exists -> fix that
-> Go over string storage (create_name) and make sure it's all stored in the string table
-> Create a separate pool for UPDATE_AFTER_BIND vulkan_renderer_resource_bind_group.odin