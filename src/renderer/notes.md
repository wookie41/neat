### Vertex Layout. 

- Each mesh is expected to have the following attributes
    - Position (float3)
    - UV (float2)
    - Normal (float3)
    - Tangent (float3)
    - SkinningIndices (uint4)   -> SkinningOnly
    - SkinningWeights (float4)  -> SkinningOnly

- If any of the attributes is missing, a zero-buffer is going to be bound for it, so the GPU
has something to index into (it has to be large enough not to cause out-of-bounds error).

- In case of a non-skinned mesh, the skinning attributes are simply `if-defed` out

### Shadow passes

- Handle vertex offset in the shadow pass
- Handle discarding fragments in the fragment shader

### Renderer design

- Define required resources in the config file 
    - Images
    - Buffers
- List available shaders in the the config file
    - associate a friendly name with the shader
    - path to the shader file
- RenderTasks are the topmost entities in the renderer, they are listed in the configuration file,
  the renderer will then execute them from top to bottom
    - Each RenderTask has to be registered manually with the renderer
    - The renderer will then call it's methods at appropriate times
    - The methods are:
        - init - grab/create the required resources
        - run - do whatever the RenderTask needs to do
        - deinit - cleanup the created resources
- Code is responsible for registering the RenderTasks with appropirate names, so they can be referenc in the config
- There will be the following RenderTask types:
    - RenderPass
        - inputs to bind (resource, stage)
        - outputs to bind (resource, stage)
        - vertex shader program
        - fragment shader program
        - uniform buffers (per frame, view, instance)
        - dynamic pipeline states
    - ComputePass
        - inputs (resource, stage)
        - outputs (resource, stage)
        - compute program
    - MaterialsRenderPass:
        - inputs (resource, stage)
        - outputs (resource, stage)
        - name of the MaterialPasses that should be used
        - uniform buffers (per frame, view, instance)
        Then there's also the MaterialPass which has:
            - vertex shader program
            - fragment shader program
            - list of features that should be injected into the vertex/fragment programs, so their code can be altered
            - dynamic pipeline states
            - the materials then reference the MaterialsPasses and that makes the makes that's what creates the draw commands
    - Any custom ones, that we might need. In this case it just has to be registered under the appropriate name.

### Pipeline handling
- Descriptor set layout that make up the pipeline layout:
    Graphics pipeline: 
        - Bindless array        (set = 0, binding = 0)
        - Immutable samplers    (set = 0, binding = 1)

        - Per frame             (set = 1, binding = 0) (dynamic offset bound)
        - Per view              (set = 1, binding = 1) (dynamic offset bound)
        - Per draw              (set = 2, binding = 0) (dynamic offset bound)
        
        - Custom bindings       (set = 2, binding = 1...n)
- Pipeline state: 
    - Created when parsing the RenderPasses, as there we have:
        - vertex program
        - fragment program
        - state overrides
    (Create presets that can be referenced in the render pass, have sane defaults)
    - vertex input state (attributes, attributes binding)
    - input assembly state (primitive topology)
    - rasterizer configuration
    - multisampling
    - color blending
    - depth stencil state
    - pipeline layout
    - viewport state (make dynamic)
    - line width (make dynamic)
    - polygon mode (make dynamic)

### Resources
- Mesh
    LOD:
        - holds submeshes (each submesh can have a different material)
        - holds lods per submesh
        Submesh:
            - just a data container, holds references
                - Material
                - Vertex
                - Index
                - AABS
                - etc.
- MeshInstance
    - this is what actually generates draw commands
    - holds a ref to the Mesh and the number of LOD to use
    - when the mesh is loaded, it find which MaterialPasses it's materials belong to and adds itself 
      to all of them
- Material
- Image
- Image view

All resources support the following interface:
1. Fill ResourceInfo structure
2. Call the appropriate createResource method
3. Get a handle back. With this handle, one can call procedures that do something with the resource.
4. Call destroyResource when we're done with it.


Things needed to create a RenderPass:
    - RenderTargets
    - PSO
        - vertex attributes
        - input assembly
        - rasterizer 
            ...
        - PSO Layout
            - buffers
            - images
            - samplers
        - Descriptor set layout 
        - Who binds the descriptor set?
            - As we're using dynamic_rendering, the PSO holds the formats of the RenderTargets,
              so a RenderPass should actually store the actual images that we should use.
              It should also have a way to update them.
              BaseRenderPass is then an extension of RenderPass that holds he DescriptorSet to bind,
              same way MaterialRenderPass is an extension of the RenderPass.
              RenderPass should hold only the images, that is inherited by Base/MaterialRenderPass
              BaseRenderPass also holds the DescriptorSet, where in case of the MaterialRenderPass, DescriptorSet would
              be stored on the MaterialInstance.
            - For material passes, each material instance should have 
              it's own DescriptorSet if we're not using bindless (textures have to be updated) 

RenderPass:
    vertexShader: program.vert
    fragmentShader: program.frag
    uniformPerFrame: PerFrame
    uniformPerView: PerView,
    uniformPerInstance: PerInstance,
    state overrides: ...
     ..viewport
     ..scissors - w need sane default for both, meaning full res, ets
    Inputs: [
        {
            Type: Image,
            Resource: SomeTexture,
        },
        {
            Type: Buffer,
            Resource: SomeBuffer 
        }
    ]
    Targets: [
        { 
            Type: Color,
            Resource: MyColorImage,
        }
    ]

This gets turned into a RenderPass that holds a reference to:
    - PSO
    - DescriptorSet
    - RenderingAttachments

and then

vkCmdPipelineBarrier 
vkBeginRendering
vkBindPipeline
vkCmdSetViewport <- call at the beginning and only when it changes
vkCmdSetScissors <- call at the beginning and only when it changes
vkCmdBindDescriptorSets

draw calls here...


----- 

Buffers

- Uniform buffers
    - updated from the CPU with different frequency
        - per frame
        - per view
        - per instance
    - we'll probably just map them and write from the CPU
- Storage buffers
    - same as uniform buffers, but can be written by/have variable sized arr ays

Patterns:
    - Wrote by the CPU every frame, read by the GPU
    - Wrote by the GPU and used by the GPU

Update strategies:
    - directly written from the CPU via a mapped buffer
        - have to be submitted at the end of the current frame/beginning of
          the next frame
    - written by the CPU to a mapped buffer, then transfered to the GPU
        - those can be submited mid frame and have a barrier placed for them
          so the next frame doesn't try to use it 

Usage patterns:
    - uniform/storage data
    - vertex buffers (streaming candidate - populated with )
    - index buffers (streaming)


Descriptor