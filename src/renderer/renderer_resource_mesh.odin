
package renderer
//---------------------------------------------------------------------------//

import "../common"
import "core:c"
import "core:log"
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

@(private = "file")
INTERNAL: struct {
	// Global vertex buffer for mesh data
	vertex_buffer_ref: BufferRef,
	// Global index buffer for mesh data
	index_buffer_ref:  BufferRef,
}

//---------------------------------------------------------------------------//

MeshDescFlagBits :: enum u16 {
	Indexed,
}

MeshDescFlags :: distinct bit_set[MeshDescFlagBits;u16]

//---------------------------------------------------------------------------//

MeshFeatureFlagBits :: enum u16 {
	Normal,
	UV,
	Tangent,
}

MeshFeatureFlags :: distinct bit_set[MeshFeatureFlagBits;u16]

//---------------------------------------------------------------------------//

SubMesh :: struct {
	index_offset:          u32, // in number of indices
	index_count:           u32,
	vertex_offset:         u32, // in number of vertices
	vertex_count:          u32,
	material_instance_ref: MaterialInstanceRef,
}

//---------------------------------------------------------------------------//

MeshDesc :: struct {
	name:           common.Name,
	// Misc flags, telling is if mesh is using indexed draw or not etc.
	flags:          MeshDescFlags,
	// Flags specyfing which features the mesh has (position, normals, UVs etc.)
	features:       MeshFeatureFlags,
	// List of submeshes that actually define the ranges in vertex/index data
	sub_meshes:     []SubMesh,
	// Mesh data
	indices:        []INDEX_DATA_TYPE,
	position:       []glsl.vec3,
	uv:             []glsl.vec2,
	normal:         []glsl.vec3,
	tangent:        []glsl.vec3,
	// Allocator that was used to allocate memory for the vertex and index data 
	data_allocator: mem.Allocator,
	file_mapping:   common.FileMemoryMapping,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshDataUploadContext :: struct {
	mesh_ref:               u32,
	finished_uploads_count: u8,
	needed_uploads_count:   u8,
}

//---------------------------------------------------------------------------//

MeshResource :: struct {
	desc:                     MeshDesc,
	vertex_count:             u32,
	index_count:              u32,
	vertex_buffer_allocation: BufferSuballocation,
	index_buffer_allocation:  BufferSuballocation,
	data_upload_context:      MeshDataUploadContext,
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

//---------------------------------------------------------------------------//

init_meshes :: proc() -> bool {

	G_MESH_REF_ARRAY = common.ref_array_create(
		MeshResource,
		MAX_MESHES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.meshes = make_soa(
		#soa[]MeshResource,
		MAX_MESHES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	// Create vertex buffer for mesh data
	{
		using INTERNAL
		vertex_buffer_ref = buffer_allocate(common.create_name("MeshVertexBuffer"))
		vertex_buffer := &g_resources.buffers[buffer_get_idx(vertex_buffer_ref)]

		vertex_buffer.desc.size = VERTEX_BUFFER_SIZE
		vertex_buffer.desc.usage = {.VertexBuffer, .TransferDst}
		vertex_buffer.desc.flags = {.Dedicated}
		buffer_create(vertex_buffer_ref) or_return
	}

	// Create index buffer for mesh data
	{
		using INTERNAL
		index_buffer_ref = buffer_allocate(common.create_name("MeshIndexBuffer"))
		index_buffer := &g_resources.buffers[buffer_get_idx(index_buffer_ref)]

		index_buffer.desc.size = INDEX_BUFFER_SIZE
		index_buffer.desc.usage = {.IndexBuffer, .TransferDst}
		index_buffer.desc.flags = {.Dedicated}
		buffer_create(index_buffer_ref) or_return
	}

	return true
}

//---------------------------------------------------------------------------//

deinit_meshes :: proc() {
}

//---------------------------------------------------------------------------//

create_mesh :: proc(p_mesh_ref: MeshRef) -> bool {
	mesh := &g_resources.meshes[get_mesh_idx(p_mesh_ref)]

	index_count := len(mesh.desc.indices)
	vertex_count := len(mesh.desc.position)

	mesh.index_count = u32(index_count)
	mesh.vertex_count = u32(vertex_count)

	// Check if the data that is actually provided has the expected number of elements
	assert(len(mesh.desc.uv) == 0 || len(mesh.desc.uv) == vertex_count)
	assert(len(mesh.desc.normal) == 0 || len(mesh.desc.normal) == vertex_count)
	assert(len(mesh.desc.tangent) == 0 || len(mesh.desc.tangent) == vertex_count)

	assert(
		.Indexed in mesh.desc.flags && len(mesh.desc.indices) > 0 ||
		(.Indexed in mesh.desc.flags) == false && len(mesh.desc.indices) == 0,
	)

	vertex_data_size := VERTEX_STRIDE * vertex_count
	index_data_size := index_count * size_of(INDEX_DATA_TYPE)

	// @TODO check if we can fit it into index and vertex buffer


	// Suballocate the vertex buffer
	vertex_allocation_successful, vertex_allocation := buffer_suballocate(
		INTERNAL.vertex_buffer_ref,
		u32(vertex_data_size),
	)

	if vertex_allocation_successful == false {
		log.warnf("Failed to load mesh - failed to suballocate vertex buffer")
		return false
	}

	// Prepare mesh data upload context
	mesh.data_upload_context = MeshDataUploadContext {
		mesh_ref               = p_mesh_ref.ref,
		finished_uploads_count = 0,
		needed_uploads_count   = 0,
	}

	// Upload index data 
	if .Indexed in mesh.desc.flags {
		index_allocation_successful, index_allocation := buffer_suballocate(
			INTERNAL.index_buffer_ref,
			u32(index_data_size),
		)

		if index_allocation_successful == false {
			buffer_free(INTERNAL.vertex_buffer_ref, vertex_allocation.vma_allocation)
			log.warnf("Failed to load mesh - failed to suballocate index buffer")
			return false
		}

		index_buffer_upload_request := BufferUploadRequest {
			dst_buff = INTERNAL.index_buffer_ref,
			dst_buff_offset = index_allocation.offset,
			dst_queue_usage = .Graphics,
			first_usage_stage = .VertexInput,
			size = u32(index_data_size),
			flags = {.RunSliced},
			data_ptr = raw_data(mesh.desc.indices),
			async_upload_callback_user_data = &mesh.data_upload_context,
			async_upload_finished_callback = mesh_upload_finished_callback,
		}

		buffer_upload_request_upload(index_buffer_upload_request)
		mesh.data_upload_context.needed_uploads_count += 1

		mesh.index_buffer_allocation = index_allocation
	}

	// Upload vertex data 
	{
		positions_size := u32(vertex_count * size_of(glsl.vec3))
		uvs_size: u32 = 0
		normals_size: u32 = 0
		tangents_size: u32 = 0

		positions_upload_request := BufferUploadRequest {
			dst_buff = INTERNAL.vertex_buffer_ref,
			dst_buff_offset = vertex_allocation.offset,
			dst_queue_usage = .Graphics,
			first_usage_stage = .VertexInput,
			size = positions_size,
			data_ptr = raw_data(mesh.desc.position),
			flags = {.RunSliced},
			async_upload_callback_user_data = &mesh.data_upload_context,
			async_upload_finished_callback = mesh_upload_finished_callback,
		}

		buffer_upload_request_upload(positions_upload_request)
		mesh.data_upload_context.needed_uploads_count += 1

		if .UV in mesh.desc.features {
			uvs_size = u32(vertex_count * size_of(glsl.vec2))
			uvs_upload_request := BufferUploadRequest {
				dst_buff = INTERNAL.vertex_buffer_ref,
				dst_buff_offset = vertex_allocation.offset + positions_size,
				dst_queue_usage = .Graphics,
				first_usage_stage = .VertexInput,
				size = uvs_size,
				data_ptr = raw_data(mesh.desc.uv),
				flags = {.RunSliced},
				async_upload_callback_user_data = &mesh.data_upload_context,
				async_upload_finished_callback = mesh_upload_finished_callback,
			}
			buffer_upload_request_upload(uvs_upload_request)
			mesh.data_upload_context.needed_uploads_count += 1
		}

		if .Normal in mesh.desc.features {
			normals_size = u32(vertex_count * size_of(glsl.vec3))
			normals_upload_request := BufferUploadRequest {
				dst_buff = INTERNAL.vertex_buffer_ref,
				dst_buff_offset = vertex_allocation.offset + positions_size + uvs_size,
				dst_queue_usage = .Graphics,
				first_usage_stage = .VertexInput,
				size = normals_size,
				data_ptr = raw_data(mesh.desc.normal),
				flags = {.RunSliced},
				async_upload_callback_user_data = &mesh.data_upload_context,
				async_upload_finished_callback = mesh_upload_finished_callback,
			}
			buffer_upload_request_upload(normals_upload_request)
			mesh.data_upload_context.needed_uploads_count += 1
		}

		if .Tangent in mesh.desc.features {
			tangents_size = u32(vertex_count * size_of(glsl.vec3))
			tangents_upload_request := BufferUploadRequest {
				dst_buff = INTERNAL.vertex_buffer_ref,
				dst_buff_offset = vertex_allocation.offset + positions_size + uvs_size + normals_size,
				dst_queue_usage = .Graphics,
				first_usage_stage = .VertexInput,
				size = tangents_size,
				data_ptr = raw_data(mesh.desc.tangent),
				flags = {.RunSliced},
				async_upload_callback_user_data = &mesh.data_upload_context,
				async_upload_finished_callback = mesh_upload_finished_callback,
			}
			buffer_upload_request_upload(tangents_upload_request)
			mesh.data_upload_context.needed_uploads_count += 1
		}
		
	}

	mesh.vertex_buffer_allocation = vertex_allocation

	return true
}

//---------------------------------------------------------------------------//

allocate_mesh_ref :: proc(p_name: common.Name, p_num_submeshes: u32) -> MeshRef {
	ref := MeshRef(common.ref_create(MeshResource, &G_MESH_REF_ARRAY, p_name))
	reset_mesh_ref(ref)
	mesh := &g_resources.meshes[get_mesh_idx(ref)]
	mesh.desc.name = p_name
	mesh.desc.sub_meshes = make(
		[]SubMesh,
		p_num_submeshes,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	return ref
}

//---------------------------------------------------------------------------//

reset_mesh_ref :: proc(p_mesh_ref: MeshRef) {
	mesh := &g_resources.meshes[get_mesh_idx(p_mesh_ref)]
	mesh^ = MeshResource{}
}

//---------------------------------------------------------------------------//

get_mesh_idx :: proc(p_ref: MeshRef) -> u32 {
	return common.ref_get_idx(&G_MESH_REF_ARRAY, p_ref)
}

//--------------------------------------------------------------------------//

destroy_mesh :: proc(p_ref: MeshRef) {
	mesh := &g_resources.meshes[get_mesh_idx(p_ref)]

	delete(mesh.desc.sub_meshes, G_RENDERER_ALLOCATORS.resource_allocator)

	// Free index and vertex data
	buffer_free(INTERNAL.index_buffer_ref, mesh.index_buffer_allocation.vma_allocation)
	buffer_free(INTERNAL.vertex_buffer_ref, mesh.vertex_buffer_allocation.vma_allocation)
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


find_mesh :: proc {
	find_mesh_by_name,
	find_mesh_by_str,
}

//---------------------------------------------------------------------------//

find_mesh_by_name :: proc(p_name: common.Name) -> MeshRef {
	ref := common.ref_find_by_name(&G_MESH_REF_ARRAY, p_name)
	if ref == InvalidMeshRef {
		return InvalidMeshRef
	}
	return MeshRef(ref)
}

//--------------------------------------------------------------------------//

find_mesh_by_str :: proc(p_str: string) -> MeshRef {
	return find_mesh_by_name(common.create_name(p_str))
}

//--------------------------------------------------------------------------//

@(private)
mesh_upload_finished_callback :: proc(p_user_data: rawptr) {
	mesh_data_upload_ctx := (^MeshDataUploadContext)(p_user_data)

	mesh_ref: MeshRef
	mesh_ref.ref = mesh_data_upload_ctx.mesh_ref

	if common.ref_is_alive(&G_MESH_REF_ARRAY, mesh_ref) == false {
		log.warnf("Upload ongoing for mesh that's not alive anymore\n")
		return
	}

	mesh_data_upload_ctx.finished_uploads_count += 1
	if mesh_data_upload_ctx.finished_uploads_count == mesh_data_upload_ctx.needed_uploads_count {
		mesh := &g_resources.meshes[get_mesh_idx(mesh_ref)]
		if mesh.desc.file_mapping.mapped_ptr != nil {
			common.unmap_file(mesh.desc.file_mapping)
			return
		}

		delete(mesh.desc.position, mesh.desc.data_allocator)
		if mesh.desc.indices != nil {
			delete(mesh.desc.indices, mesh.desc.data_allocator)
		}

		if mesh.desc.uv != nil {
			delete(mesh.desc.uv, mesh.desc.data_allocator)
		}

		if mesh.desc.normal != nil {
			delete(mesh.desc.normal, mesh.desc.data_allocator)
		}

		if mesh.desc.tangent != nil {
			delete(mesh.desc.tangent, mesh.desc.data_allocator)
		}
	}
}

//--------------------------------------------------------------------------//
