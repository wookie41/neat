TODO:
- create a common way to request uniform data based on a struct
- move the instanced draws buffers into the mesh render task specific bind group
- anisotrophy
- use smaller presision for vertex attributes
- create a helper function for binding mesh vertex attributes
- non-uniform scale support for normal matrix
- get rid of render_passes.json. Instead, create them based on the image formats and reuse based on that
- add an option to initialize an image with color and make the default texture white

INPROGRESS

DONE:
- add per frame data
- fix normal mapping
- add debug markers
- basic pbr brdf setup
- fix shader hot reload crashes
- fix swapchain resizing