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
INDEX_DATA_TYPE :: u32
@(private = "file")
ZERO_VECTOR := glsl.vec4{0, 0, 0, 0}
@(private = "file")
VERTEX_STRIDE :: size_of(glsl.vec3) + size_of(glsl.vec2) + size_of(glsl.vec3) + size_of(glsl.vec3) // Position// UV// Normal// Tangetn

//---------------------------------------------------------------------------//


// Array where we store refs of the meshes that were created during this frame 
// so that different systems get a chance to react to it. 
// For example, the mesh render can create and store draw commands.
@(private)
g_created_mesh_refs: [dynamic]MeshRef

@(private)
g_destroyed_mesh_refs: [dynamic]MeshRef

//---------------------------------------------------------------------------//


@(private = "file")
INTERNAL: struct {
	// Global vertex buffer for mesh data
	vertex_buffer_ref: BufferRef,
	// Global index buffer for mesh data
	index_buffer_ref:  BufferRef,
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
	// Offset and number of vertices/indices for this submesh
	// Usage depends on wether the mesh is using indexed draw or not
	data_offset: u32,
	data_count:  u32,
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

MeshRef :: common.Ref(MeshResource)

//---------------------------------------------------------------------------//

InvalidMeshRef := MeshRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_REF_ARRAY: common.RefArray(MeshResource)
@(private = "file")
G_MESH_RESOURCE_ARRAY: []MeshResource

//---------------------------------------------------------------------------//

init_meshes :: proc() -> bool {

	g_created_mesh_refs = make([dynamic]MeshRef, G_RENDERER_ALLOCATORS.frame_allocator)
	g_destroyed_mesh_refs = make([dynamic]MeshRef, G_RENDERER_ALLOCATORS.frame_allocator)

	G_MESH_REF_ARRAY = common.ref_array_create(
		MeshResource,
		MAX_MESHES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	G_MESH_RESOURCE_ARRAY = make(
		[]MeshResource,
		MAX_MESHES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

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

	// Create index buffer for mesh data
	{
		using INTERNAL
		index_buffer_ref = allocate_buffer_ref(common.create_name("MeshIndexBuffer"))
		index_buffer := get_buffer(index_buffer_ref)

		index_buffer.desc.size = INDEX_BUFFER_SIZE
		index_buffer.desc.usage = {.IndexBuffer, .TransferDst}
		index_buffer.desc.flags = {.Dedicated}
		create_buffer(index_buffer_ref) or_return
	}

	return true
}

//---------------------------------------------------------------------------//

deinit_meshes :: proc() {
}

//---------------------------------------------------------------------------//

create_mesh :: proc(p_mesh_ref: MeshRef) -> bool {
	mesh := get_mesh(p_mesh_ref)

	index_count := len(mesh.desc.indices)
	vertex_count := len(mesh.desc.position)

	// Check if the data that is actually provided has the expected number of elements
	assert(len(mesh.desc.uv) == 0 || len(mesh.desc.uv) == vertex_count)
	assert(len(mesh.desc.normal) == 0 || len(mesh.desc.normal) == vertex_count)
	assert(len(mesh.desc.tangent) == 0 || len(mesh.desc.tangent) == vertex_count)

	assert(
		.Indexed in mesh.desc.flags && len(mesh.desc.indices) > 0 ||
		(.Indexed in mesh.desc.flags) == false && len(mesh.desc.indices) == 0,
	)

	// Check if the the uplaod requests will fit into the staging buffer
	vertex_data_size := VERTEX_STRIDE * vertex_count
	index_data_size := index_count * size_of(INDEX_DATA_TYPE)

	if dry_request_buffer_upload(
		   INTERNAL.vertex_buffer_ref,
		   u32(vertex_data_size + index_data_size),
	   ) ==
	   false {
		return false
	}

	// Suballocate the vertex and index buffers
	vertex_allocation_successful, vertex_allocation := buffer_allocate(
		INTERNAL.vertex_buffer_ref,
		u32(vertex_data_size),
	)

	if vertex_allocation_successful == false {
		return false
	}

	index_allocation_successful, index_allocation := buffer_allocate(
		INTERNAL.index_buffer_ref,
		u32(index_data_size),
	)

	if index_allocation_successful == false {
		buffer_free(INTERNAL.vertex_buffer_ref, vertex_allocation.vma_allocation)
		return false
	}

	// Upload index data to the staging buffer
	if .Indexed in mesh.desc.flags {
		index_buffer_upload_request := BufferUploadRequest {
			dst_buff          = INTERNAL.index_buffer_ref,
			dst_buff_offset   = index_allocation.offset,
			dst_queue_usage   = .Graphics,
			first_usage_stage = .VertexInput,
			size              = u32(index_data_size),
		}

		upload_response := request_buffer_upload(index_buffer_upload_request)

		mem.copy(
			upload_response.ptr,
			raw_data(mesh.desc.indices),
			size_of(INDEX_DATA_TYPE) * index_count,
		)
	}

	// Upload vertex data to the staging buffer
	{
		vertex_buffer_upload_request := BufferUploadRequest {
			dst_buff          = INTERNAL.vertex_buffer_ref,
			dst_buff_offset   = vertex_allocation.offset,
			dst_queue_usage   = .Graphics,
			first_usage_stage = .VertexInput,
			size              = u32(vertex_data_size),
		}

		upload_response := request_buffer_upload(vertex_buffer_upload_request)

		vertex_data_ptr := (^byte)(upload_response.ptr)

		// Upload data and pad with 0s if neccessary 
		for i in 0 ..< vertex_count {
			mem.copy(
				mem.ptr_offset(vertex_data_ptr, VERTEX_STRIDE * i),
				&mesh.desc.position[i],
				size_of(mesh.desc.position[0]),
			)
		}

		// UV
		if .UV in mesh.desc.features {
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i + size_of(mesh.desc.position[0]),
					),
					&mesh.desc.uv[i],
					size_of(mesh.desc.uv[0]),
				)
			}
		} else {
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i + size_of(mesh.desc.position[0]),
					),
					&ZERO_VECTOR,
					size_of(mesh.desc.uv[0]),
				)
			}
		}

		// Normal
		if .Normal in mesh.desc.features {
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]),
					),
					&mesh.desc.normal[i],
					size_of(mesh.desc.normal[0]),
				)
			}
		} else {
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i +
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
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]) +
						size_of(mesh.desc.normal[0]),
					),
					&mesh.desc.tangent[i],
					size_of(mesh.desc.tangent[0]),
				)
			}
		} else {
			for i in 0 ..< vertex_count {
				mem.copy(
					mem.ptr_offset(
						vertex_data_ptr,
						VERTEX_STRIDE * i +
						size_of(mesh.desc.position[0]) +
						size_of(mesh.desc.uv[0]) +
						size_of(mesh.desc.normal[0]),
					),
					&ZERO_VECTOR,
					size_of(mesh.desc.tangent[0]),
				)
			}
		}
	}

	mesh.index_buffer_allocation = index_allocation
	mesh.vertex_buffer_allocation = vertex_allocation

	append(&g_created_mesh_refs, p_mesh_ref)

	return true
}

//---------------------------------------------------------------------------//

allocate_mesh_ref :: proc(p_name: common.Name) -> MeshRef {
	ref := MeshRef(common.ref_create(MeshResource, &G_MESH_REF_ARRAY, p_name))
	get_mesh(ref).desc.name = p_name
	return ref
}
//---------------------------------------------------------------------------//

get_mesh :: proc(p_ref: MeshRef) -> ^MeshResource {
	return &G_MESH_RESOURCE_ARRAY[common.ref_get_idx(&G_MESH_REF_ARRAY, p_ref)]
}

//--------------------------------------------------------------------------//

destroy_mesh :: proc(p_ref: MeshRef) {
	mesh := get_mesh(p_ref)

	// Free index and vertex data
	buffer_free(INTERNAL.index_buffer_ref, mesh.index_buffer_allocation.vma_allocation)

	buffer_free(INTERNAL.vertex_buffer_ref, mesh.vertex_buffer_allocation.vma_allocation)

	// Add the mesh ref to the destroyed meshes queue
	append(&g_created_mesh_refs, p_ref)
}

//--------------------------------------------------------------------------//

@(private)
free_mesh_ref :: proc(p_mesh_ref: MeshRef) {
	common.ref_free(&G_MESH_REF_ARRAY, p_mesh_ref)

}

//--------------------------------------------------------------------------//

@(private)
mesh_get_global_vertex_buffer_ref :: proc() -> BufferRef {
	return INTERNAL.vertex_buffer_ref
}

//--------------------------------------------------------------------------//

@(private)
mesh_get_global_index_buffer_ref :: proc() -> BufferRef {
	return INTERNAL.index_buffer_ref
}

//--------------------------------------------------------------------------//
