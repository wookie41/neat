package renderer

import "../common"

TextureBinding :: struct {
	name:      common.Name,
	image_ref: ImageRef,
}

BufferBinding :: struct {
	name:       common.Name,
	buffer_ref: BufferRef,
}

BindGroup :: struct {
	textures: []TextureBinding,
	buffers:  []BufferBinding,
}
