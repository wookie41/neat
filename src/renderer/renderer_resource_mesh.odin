package renderer

//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:math/linalg/glsl"
import "core:mem"

//---------------------------------------------------------------------------//

@(private = "file")
VERTEX_BUFFER_SIZE :: 512 * common.MEGABYTE
@(private = "file")
INDEX_BUFFER_SIZE :: 128 * common.MEGABYTE

@(private = "file")
VERTEX_UPLOAD_BUFFER_SIZE :: 64 * common.MEGABYTE
@(private = "file")
INDEX_UPLOAD_BUFFER_SIZE :: 64 * common.MEGABYTE
@(private = "file")
INDEX_DATA_TYPE :: u16
@(private = "file")
ZERO_VECTOR := glsl.vec4{0, 0, 0, 0}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	// Global vertex buffer for mesh data
	vertex_buffer_ref:           BufferRef,
	// Staging vertex buffer used to upload data to the GPU
	vertex_upload_buffer_ref:    BufferRef,
	// Global index buffer for mesh data
	index_buffer_ref:            BufferRef,
	// Staging index buffer used to upload data to the GPU
	index_upload_buffer_ref:     BufferRef,
	// Current offset into the vertex staging buffer
	vertex_upload_buffer_offset: u32,
	// Current offset into the index staging buffer
	index_upload_buffer_offset:  u32,
}

//---------------------------------------------------------------------------//


MeshFlagBits :: enum u16 {
	Indexed,
}

MeshFlags :: distinct bit_set[MeshFlagBits;u16]

//---------------------------------------------------------------------------//

MeshFeatureFlagBits :: enum u16 {
	Normal,
	UV,
	Tangent,
}

MeshFeatureFlags :: distinct bit_set[MeshFeatureFlagBits;u16]

//---------------------------------------------------------------------------//

SubMesh :: struct {
	vertex_offset: u32,
	vertex_count:  u32,
}

//---------------------------------------------------------------------------//

MeshDesc :: struct {
	name:       common.Name,
	// Misc flags, telling is if mesh is using indexed draw or not etc.
	flags:      MeshFlags,
	// Flags specyfing which features the mesh has (position, normals, UVs etc.)
	features:   MeshFeatureFlags,
	// List of submeshes that actually define the ranges in vertex/index data
	sub_meshes: []SubMesh,
	// Mesh data
	indices:    []INDEX_DATA_TYPE,
	position:   []glsl.vec3,
	uv:         []glsl.vec2,
	normal:     []glsl.vec3,
	tangent:    []glsl.vec3,
}

//---------------------------------------------------------------------------//

MeshResource :: struct {
	desc:                     MeshDesc,
	vertex_buffer_allocation: BufferSuballocation,
	index_buffer_allocation:  BufferSuballocation,
}

//---------------------------------------------------------------------------//

MeshRef :: Ref(MeshResource)

//---------------------------------------------------------------------------//

InvalidMeshRef := MeshRef {
	ref = c.UINT64_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_REF_ARRAY: RefArray(MeshResource)

//---------------------------------------------------------------------------//


init_meshes :: proc() -> bool {
	G_MESH_REF_ARRAY = create_ref_array(MeshResource, MAX_MESHES)

	// Create vertex buffer for mesh data
	{
		using INTERNAL
		vertex_buffer_ref = allocate_buffer_ref(common.create_name("MeshVertexBuffer"))
		vertex_buffer := get_buffer(vertex_buffer_ref)

		vertex_buffer.desc.size = VERTEX_BUFFER_SIZE
		vertex_buffer.desc.usage = {.VertexBuffer, .TransferDst}
		vertex_buffer.desc.flags = {.Dedicated}
		create_buffer(vertex_buffer_ref) or_return
	}

	// Create vertex upload buffer 
	{
		using INTERNAL
		vertex_upload_buffer_ref = allocate_buffer_ref(
			common.create_name("MeshVertexUploadBuffer"),
		)
		vertex_upload_buffer := get_buffer(vertex_upload_buffer_ref)

		vertex_upload_buffer.desc.size = VERTEX_UPLOAD_BUFFER_SIZE
		vertex_upload_buffer.desc.usage = {.VertexBuffer, .TransferSrc}
		vertex_upload_buffer.desc.flags = {.HostWrite, .Mapped}
		create_buffer(vertex_upload_buffer_ref) or_return
	}

	// Create index buffer for mesh data
	{
		using INTERNAL
		index_buffer_ref = allocate_buffer_ref(common.create_name("MeshIndexBuffer"))
		index_buffer := get_buffer(index_buffer_ref)

		index_buffer.desc.size = INDEX_BUFFER_SIZE
		index_buffer.desc.usage = {.TransferSrc}
		index_buffer.desc.flags = {.Dedicated}
		create_buffer(index_buffer_ref) or_return
	}

	// Create index upload buffer 
	{
		using INTERNAL
		index_upload_buffer_ref = allocate_buffer_ref(
			common.create_name("MeshIndexUploadBuffer"),
		)
		index_upload_buffer := get_buffer(index_upload_buffer_ref)

		index_upload_buffer.desc.size = INDEX_UPLOAD_BUFFER_SIZE
		index_upload_buffer.desc.usage = {.TransferSrc}
		index_upload_buffer.desc.flags = {.HostWrite, .Mapped}
		create_buffer(index_upload_buffer_ref) or_return
	}

	return true
}

//---------------------------------------------------------------------------//

deinit_meshes :: proc() {
}

//---------------------------------------------------------------------------//

create_mesh :: proc(p_mesh_ref: MeshRef) -> bool {
	mesh := get_mesh(p_mesh_ref)

	total_vertex_count: int = 0

	// Calculate the total number of vertices
	for sub_mesh in mesh.desc.sub_meshes {
		total_vertex_count += int(sub_mesh.vertex_count)
	}

	// Check if the data that is actually provided has the expected number of elements
	assert(len(mesh.desc.position) == total_vertex_count)
	assert(len(mesh.desc.uv) == 0 || len(mesh.desc.uv) == total_vertex_count)
	assert(len(mesh.desc.normal) == 0 || len(mesh.desc.normal) == total_vertex_count)
	assert(len(mesh.desc.tangent) == 0 || len(mesh.desc.tangent) == total_vertex_count)

	// Prepare the data that we're going to transfer to the GPU
	// pad the missing features with 0s
	total_mesh_data_size :=
		(size_of(mesh.desc.position[0]) +
			size_of(mesh.desc.uv[0]) +
			size_of(mesh.desc.normal[0]) +
			size_of(mesh.desc.tangent[0])) *
		total_vertex_count


	// Abort if we don't have enough space in vertex buffers
	{
		no_space_in_upload_buffer :=
			INTERNAL.vertex_upload_buffer_offset + u32(total_mesh_data_size) >
			VERTEX_UPLOAD_BUFFER_SIZE

		allocation_successful, allocation := buffer_allocate(
			INTERNAL.vertex_buffer_ref,
			u32(total_mesh_data_size),
		)

		if no_space_in_upload_buffer || allocation_successful == false {
			return false
		}

		mesh.vertex_buffer_allocation = allocation
	}

	// Abort if we don't have enough space in index buffers
	{
		no_space_in_upload_buffer :=
			INTERNAL.index_upload_buffer_offset +
				u32(total_vertex_count) * u32(size_of(INDEX_DATA_TYPE)) >
			VERTEX_UPLOAD_BUFFER_SIZE

		allocation_successful, allocation := buffer_allocate(
			INTERNAL.vertex_buffer_ref,
			u32(total_mesh_data_size),
		)

		if no_space_in_upload_buffer || allocation_successful == false {
			buffer_free(
				INTERNAL.vertex_buffer_ref,
				mesh.vertex_buffer_allocation.vma_allocation,
			)
			return false
		}

		mesh.index_buffer_allocation = allocation
	}

	// Move index data to the upload buffer
	{
		index_upload_buffer := get_buffer(INTERNAL.index_upload_buffer_ref)

		mem.copy(
			mem.ptr_offset(
				index_upload_buffer.mapped_ptr,
				INTERNAL.index_upload_buffer_offset,
			),
			raw_data(mesh.desc.indices),
			size_of(INDEX_DATA_TYPE) * total_vertex_count,
		)

		INTERNAL.index_upload_buffer_offset +=
			u32(size_of(INDEX_DATA_TYPE)) * u32(total_vertex_count)
	}

	// Move vertex data to the upload buffer
	{
		// Calculate the stride
		stride := size_of(mesh.desc.position[0])

		if .UV in mesh.desc.features {
			stride += size_of(mesh.desc.uv[0])
		}

		if .Normal in mesh.desc.features {
			stride += size_of(mesh.desc.normal[0])
		}

		if .Tangent in mesh.desc.features {
			stride += size_of(mesh.desc.tangent[0])
		}

		vertex_upload_buffer := get_buffer(INTERNAL.vertex_upload_buffer_ref)

		// Upload data and pad with 0s if neccessary 
		for i in 0 ..< total_vertex_count {

			mem.copy(
				mem.ptr_offset(
					vertex_upload_buffer.mapped_ptr,
					int(INTERNAL.vertex_upload_buffer_offset) + stride * i,
				),
				&mesh.desc.position[i],
				size_of(mesh.desc.position[0]),
			)
		}

		// UV
		if .UV in mesh.desc.features {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]),
					),
					&mesh.desc.uv[i],
					size_of(mesh.desc.uv[0]),
				)
			}
		} else {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]),
					),
					&ZERO_VECTOR,
					size_of(mesh.desc.uv[0]),
				)
			}
		}

		// Normal
		if .Normal in mesh.desc.features {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]),
					),
					&mesh.desc.normal[i],
					size_of(mesh.desc.normal[0]),
				)
			}
		} else {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]),
					),
					&ZERO_VECTOR,
					size_of(mesh.desc.normal[0]),
				)
			}
		}

		// Tangent
		if .Tangent in mesh.desc.features {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]) +
						size_of(mesh.desc.normal[0]),
					),
					&mesh.desc.tangent[i],
					size_of(mesh.desc.tangent[0]),
				)
			}
		} else {
			for i in 0 ..< total_vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_upload_buffer.mapped_ptr,
						int(INTERNAL.vertex_upload_buffer_offset) +
						stride * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]) +
						size_of(mesh.desc.normal[0]),
					),
					&ZERO_VECTOR,
					size_of(mesh.desc.tangent[0]),
				)
			}
		}

		// Update the upload buffer offset
		INTERNAL.vertex_upload_buffer_offset += u32(total_mesh_data_size)
	}

	// @TODO Queue the transfer, use renderer_buffer_upload.odin 
	// (those internal pending buffers here are useless, delete them)

	return true
}

//---------------------------------------------------------------------------//

allocate_mesh_ref :: proc(p_name: common.Name) -> MeshRef {
	ref := MeshRef(create_ref(MeshResource, &G_MESH_REF_ARRAY, p_name))
	get_mesh(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_mesh :: proc(p_ref: MeshRef) -> ^MeshResource {
	return get_resource(MeshResource, &G_MESH_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_mesh :: proc(p_ref: MeshRef) {
	// mesh := get_mesh(p_ref)
	free_ref(MeshResource, &G_MESH_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//
