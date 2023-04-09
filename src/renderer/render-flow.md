Material:
- which shaders to use

MaterialPass
- MaterialRef
- features []string (shader defines)
- this compiles the shader permutation
- executed by MeshRenderTask
- holds the list of meshes to draw
    - MeshRef is cached when a MaterialInstance is paired with a Mesh
    - for debug material passes, where we want to draw all of the meshes, we'll just have a flag

MaterialInstance:
- MaterialPassRef
- bind groups 
- holds parameter values


MeshInstance
- MeshRef
- MaterialInstanceRef
- xform
- visibility mask

        []MeshInstance          mesh_instance.material_instance.material_pass
Culling ---------> MeshRenderTask -------------------------------------> Sort by MaterialPass -> Render

FrustumSet:
- set of frustums for a given camera
- camera frustum, directional light frustums to cull meshes for cascade maps

Camera
- posWS
- near, far
- projection type
- fov
- frustum ref

Frustum
- view, projection matrix
- mark visible instances
- MeshRenderTask gathers the draw commands based on material passes that were enabled
  and sorts the draw commands by material pass

Render:
 Get pipeline from the material
 Bind render task bind groups
 Get dynamic buffer offset from the material instance
 Bind material instance bind groups
 Get vertex/index buffer offsets from mesh