TODO:
- anisotrophy
- use smaller presision for vertex attributes
- create a helper function for binding mesh vertex attributes
- non-uniform scale support for normal matrix
- add an option to initialize an image with color and make the default texture white
- renderer config hot reload

INPROGRESS
- try to use the existing code to render a shadow map for the sun light

DONE:
- add per frame data
- fix normal mapping
- add debug markers
- basic pbr brdf setup
- fix shader hot reload crashes
- fix swapchain resizing
- move the instanced draws buffers into the mesh render task specific bind group
- create a common way to request uniform data based on a struct