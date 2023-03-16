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


        []MeshInstance          mesh_instance.material_instance.material_pass
Culling ---------> MeshRenderTask -------------------------------------> Sort by MaterialPass -> Render


Render:
 Get pipeline from the material
 Bind render task bind groups
 Get dynamic buffer offset from the material instance
 Bind material instance bind groups
 Get vertex/index buffer offsets from mesh