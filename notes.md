- Create a black texture on the GPU that we'll use as the default
 
- Check if the bindless descriptor set array is initialized to zeros

- In the renderer_buffer_upload.odin, handle the case when we're on UMA by:
    - Don't create a staging buffer at all
    - Mapping the buffer upon creation 
    - Returning a pointer to the mapped buffer in the response instead

- backend_create_pipeline_layout for Vulkan doesn't support compute shaders

- Make sure render targets can be bound as Textures in the shader. Right now only the bindless texture array path is tested.

- Create a cache for descriptor set layouts and resuse them (vulkan_renderer_resource_pipeline_layout.odin)

