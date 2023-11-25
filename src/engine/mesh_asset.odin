package engine

//---------------------------------------------------------------------------//

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../common"
import "../renderer"
import assimp "../third_party/assimp"

//---------------------------------------------------------------------------//

@(private = "file")
G_METADATA_FILE_VERSION :: 1

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_DB_PATH :: "app_data/engine/assets/meshes/db.json"

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_ASSETS_DIR :: "app_data/engine/assets/meshes/"

//---------------------------------------------------------------------------//

MeshAssetImportFlagBits :: enum u16 {}

MeshAssetImportFlags :: distinct bit_set[MeshAssetImportFlagBits;u16]

//---------------------------------------------------------------------------//

MeshAssetImportOptions :: struct {
	file_path: string,
	flags:     MeshAssetImportFlags,
}

//---------------------------------------------------------------------------//

MeshAssetFlagBits :: enum u16 {}

MeshAssetFlags :: distinct bit_set[MeshAssetFlagBits;u16]

//---------------------------------------------------------------------------//

MeshFeatureFlagBits :: enum u16 {
	Normal,
	UV,
	Tangent,
	IndexedDraw,
}

MeshFeatureFlags :: distinct bit_set[MeshFeatureFlagBits;u16]

//---------------------------------------------------------------------------//

@(private = "file")
SubMeshMetadata :: struct {
	data_count:          u32,
	data_offset:         u32,
	material_asset_name: common.Name,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshAssetMetadata :: struct {
	using base:        AssetMetadataBase,
	feature_flags:     MeshFeatureFlags `json:"featureFlags"`,
	sub_meshes:        []SubMeshMetadata `json:"subMeshes"`,
	total_vertex_size: u32 `json:"totalVertexSize"`,
	total_index_size:  u32 `json:"totalIndexSize"`,
	num_vertices:      u32 `json:"numVertices"`,
	num_indices:       u32 `json:"numIndices"`,
}

//---------------------------------------------------------------------------//

MeshAsset :: struct {
	using metadata: MeshAssetMetadata,
	ref_count:      u32,
	mesh_ref:       renderer.MeshRef,
}

//---------------------------------------------------------------------------//

MAX_MESH_ASSETS :: 2048

//---------------------------------------------------------------------------//

MeshAssetRef :: common.Ref(MeshAsset)

//---------------------------------------------------------------------------//

InvalidMeshAssetRef := MeshAssetRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

@(private = "file")
G_MESH_ASSET_REF_ARRAY: common.RefArray(MeshAsset)
@(private = "file")
G_MESH_ASSET_ARRAY: []MeshAsset

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	mesh_database: AssetDatabase,
}

//---------------------------------------------------------------------------//

mesh_asset_init :: proc() {

	G_MESH_ASSET_REF_ARRAY = common.ref_array_create(
		MeshAsset,
		MAX_MESH_ASSETS,
		G_ALLOCATORS.asset_allocator,
	)
	G_MESH_ASSET_ARRAY = make([]MeshAsset, MAX_MESH_ASSETS, G_ALLOCATORS.asset_allocator)

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	context.temp_allocator = temp_arena.allocator

	asset_database_init(&INTERNAL.mesh_database, G_MESH_DB_PATH)
	asset_database_read(&INTERNAL.mesh_database)
}

//---------------------------------------------------------------------------//

@(private = "file")
SubMesh :: struct {
	data_offset:         u32,
	data_count:          u32,
	vertex_offset:       u32,
	material_asset_name: common.Name,
}

//---------------------------------------------------------------------------//

@(private = "file")
MeshImportContext :: struct {
	curr_vtx:           u32,
	curr_idx:           u32,
	current_sub_mesh:   u32,
	indices:            []u32,
	positions:          []glsl.vec3,
	normals:            []glsl.vec3,
	tangents:           []glsl.vec3,
	uvs:                []glsl.vec2,
	mesh_feature_flags: MeshFeatureFlags,
	sub_meshes:         []SubMesh,
	mesh_dir:           string,
	arena:              ^common.Arena,
}

//---------------------------------------------------------------------------//

@(private = "file")
allocate_mesh_asset_ref :: proc(p_name: common.Name) -> MeshAssetRef {
	ref := MeshAssetRef(common.ref_create(MeshAsset, &G_MESH_ASSET_REF_ARRAY, p_name))
	mesh := mesh_asset_get(ref)
	mesh.name = p_name
	mesh.type = .Texture
	return ref
}

//---------------------------------------------------------------------------//

mesh_asset_get :: proc(p_ref: MeshAssetRef) -> ^MeshAsset {
	return &G_MESH_ASSET_ARRAY[common.ref_get_idx(&G_MESH_ASSET_REF_ARRAY, p_ref)]
}

//---------------------------------------------------------------------------//

mesh_asset_import :: proc(p_import_options: MeshAssetImportOptions) -> AssetImportResult {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)
	context.temp_allocator = temp_arena.allocator

	mesh_asset_name := filepath.short_stem(filepath.base(p_import_options.file_path))
	mesh_file_path := strings.clone_to_cstring(p_import_options.file_path, context.temp_allocator)

	// Check if the mesh already exits
	mesh_asset_file_name := strings.concatenate({mesh_asset_name, ".bin"}, temp_arena.allocator)
	mesh_asset_path := filepath.join(
		{G_MESH_ASSETS_DIR, mesh_asset_file_name},
		temp_arena.allocator,
	)
	if os.exists(mesh_asset_path) {
		return {status = .Duplicate, name = common.create_name(mesh_asset_name)}
	}

	scene := assimp.import_file(mesh_file_path, {.OptimizeMeshes, .Triangulate, .FlipUVs})
	if scene == nil {
		return AssetImportResult{status = .Error}
	}
	defer assimp.release_import(scene)

	mesh_import_ctx := MeshImportContext {
		curr_idx = 0,
		curr_vtx = 0,
		mesh_dir = filepath.dir(p_import_options.file_path, temp_arena.allocator),
		arena    = &temp_arena,
	}

	// Calculate the number of vertices and indices
	num_vertices: u32 = 0
	num_indices: u32 = 0

	// Assuming all submeshes will also have those features. I mean, it makes sense
	if (scene.mMeshes[0].mNormals != nil) {
		mesh_import_ctx.mesh_feature_flags += {.Normal}
	}
	if (scene.mMeshes[0].mTangents != nil) {
		mesh_import_ctx.mesh_feature_flags += {.Tangent}
	}
	if (len(scene.mMeshes[0].mTextureCoords) > 0) {
		mesh_import_ctx.mesh_feature_flags += {.UV}
	}

	for i in 0 ..< scene.mNumMeshes {
		num_vertices += u32(scene.mMeshes[i].mNumVertices)
		num_indices += u32(scene.mMeshes[i].mNumFaces * 3)
	}

	if num_indices > 0 {
		mesh_import_ctx.mesh_feature_flags += {.IndexedDraw}
		mesh_import_ctx.indices = make([]u32, int(num_indices), G_ALLOCATORS.main_allocator)
	}

	mesh_import_ctx.positions = make([]glsl.vec3, int(num_vertices), G_ALLOCATORS.main_allocator)
	mesh_import_ctx.normals = make([]glsl.vec3, int(num_vertices), G_ALLOCATORS.main_allocator)
	mesh_import_ctx.tangents = make([]glsl.vec3, int(num_vertices), G_ALLOCATORS.main_allocator)
	mesh_import_ctx.uvs = make([]glsl.vec2, int(num_vertices), G_ALLOCATORS.main_allocator)
	mesh_import_ctx.sub_meshes = make([]SubMesh, scene.mNumMeshes, G_ALLOCATORS.main_allocator)

	defer delete(mesh_import_ctx.positions, G_ALLOCATORS.main_allocator)
	defer delete(mesh_import_ctx.normals, G_ALLOCATORS.main_allocator)
	defer delete(mesh_import_ctx.tangents, G_ALLOCATORS.main_allocator)
	defer delete(mesh_import_ctx.uvs, G_ALLOCATORS.main_allocator)
	defer delete(mesh_import_ctx.sub_meshes, G_ALLOCATORS.main_allocator)
	defer delete(mesh_import_ctx.indices, G_ALLOCATORS.main_allocator)

	// Recursivly load the nodes
	assimp_load_node(scene, scene.mRootNode, &mesh_import_ctx)

	// Save the metadata
	mesh_metadata_file_path := common.aprintf(
		temp_arena.allocator,
		"%s%s.metadata",
		G_MESH_ASSETS_DIR,
		mesh_asset_name,
	)
	mesh_metadata := MeshAssetMetadata {
		name          = common.create_name(mesh_asset_name),
		uuid          = uuid_create(),
		version       = G_METADATA_FILE_VERSION,
		type          = .Mesh,
		feature_flags = mesh_import_ctx.mesh_feature_flags,
		num_vertices  = u32(len(mesh_import_ctx.positions)),
		sub_meshes    = make(
			[]SubMeshMetadata,
			len(mesh_import_ctx.sub_meshes),
			temp_arena.allocator,
		),
	}

	if .IndexedDraw in mesh_import_ctx.mesh_feature_flags {
		mesh_metadata.num_indices = u32(len(mesh_import_ctx.indices))
		mesh_metadata.total_index_size = size_of(u32) * mesh_metadata.num_indices
	}

	mesh_metadata.total_vertex_size = size_of(glsl.vec3) * mesh_metadata.num_vertices
	if .Normal in mesh_import_ctx.mesh_feature_flags {
		mesh_metadata.total_vertex_size += size_of(glsl.vec3) * mesh_metadata.num_vertices
	}
	if .Tangent in mesh_import_ctx.mesh_feature_flags {
		mesh_metadata.total_vertex_size += size_of(glsl.vec3) * mesh_metadata.num_vertices
	}
	if .UV in mesh_import_ctx.mesh_feature_flags {
		mesh_metadata.total_vertex_size += size_of(glsl.vec2) * mesh_metadata.num_vertices
	}

	for sub_mesh, i in mesh_import_ctx.sub_meshes {
		mesh_metadata.sub_meshes[i] = SubMeshMetadata {
			data_count          = sub_mesh.data_count,
			data_offset         = sub_mesh.data_offset,
			material_asset_name = sub_mesh.material_asset_name,
		}
	}

	if common.write_json_file(
		   mesh_metadata_file_path,
		   MeshAssetMetadata,
		   mesh_metadata,
		   temp_arena.allocator,
	   ) ==
	   false {
		log.warnf("Failed to save mesh '%s' - couldn't save metadata\n", mesh_asset_name)
		return AssetImportResult{status = .Error}

	}

	mesh_name := common.create_name(mesh_asset_name)

	// Save the data itself
	fd, err := os.open(mesh_asset_path, os.O_WRONLY | os.O_CREATE)
	if err != 0 {
		os.remove(mesh_metadata_file_path)
		log.warnf(
			"Failed to save mesh '%s' - couldn't open file %s\n",
			mesh_asset_name,
			mesh_asset_path,
		)

		return AssetImportResult{status = .Error}
	}

	if .IndexedDraw in mesh_import_ctx.mesh_feature_flags {
		os.write_ptr(fd, raw_data(mesh_import_ctx.indices), int(mesh_metadata.total_index_size))
	}

	os.write_ptr(fd, raw_data(mesh_import_ctx.positions), int(num_vertices) * size_of(glsl.vec3))

	if .Normal in mesh_import_ctx.mesh_feature_flags {
		os.write_ptr(fd, raw_data(mesh_import_ctx.normals), int(num_vertices) * size_of(glsl.vec3))
	}

	if .Tangent in mesh_import_ctx.mesh_feature_flags {
		os.write_ptr(
			fd,
			raw_data(mesh_import_ctx.tangents),
			int(num_vertices) * size_of(glsl.vec3),
		)
	}

	if .UV in mesh_import_ctx.mesh_feature_flags {
		os.write_ptr(fd, raw_data(mesh_import_ctx.uvs), int(num_vertices) * size_of(glsl.vec2))
	}

	// Add an entry to the database
	mesh_file_name := strings.concatenate({mesh_asset_name, ".bin"}, temp_arena.allocator)

	db_entry := AssetDatabaseEntry {
		uuid      = mesh_metadata.uuid,
		name      = mesh_asset_name,
		file_name = mesh_file_name,
	}
	asset_database_add(&INTERNAL.mesh_database, db_entry, true)

	return AssetImportResult{name = mesh_name, status = .Ok}
}

//---------------------------------------------------------------------------//

mesh_asset_load :: proc {
	mesh_asset_load_by_name,
	mesh_asset_load_by_str,
}

//---------------------------------------------------------------------------//

@(private = "file")
mesh_asset_load_by_str :: proc(p_mesh_asset_name: string) -> MeshAssetRef {
	return mesh_asset_load_by_name(common.create_name(p_mesh_asset_name))
}

//---------------------------------------------------------------------------//

@(private = "file")
mesh_asset_load_by_name :: proc(p_mesh_asset_name: common.Name) -> MeshAssetRef {

	// Check if it's already loaded
	{
		mesh_asset_ref := common.ref_find_by_name(&G_MESH_ASSET_REF_ARRAY, p_mesh_asset_name)
		if mesh_asset_ref != InvalidMeshAssetRef {
			mesh_asset_get(mesh_asset_ref).ref_count += 1
			return mesh_asset_ref
		}
	}

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)
	context.temp_allocator = temp_arena.allocator

	mesh_asset_path := asset_create_path(
		G_MESH_ASSETS_DIR,
		p_mesh_asset_name,
		"bin",
		context.temp_allocator,
	)

	// Determine how much data we need to allocate for the mesh data
	mesh_data_size := os.file_size_from_path(mesh_asset_path)

	// Allocate arena for the mesh data
	mesh_data_arena: common.Arena
	common.arena_init(&mesh_data_arena, u32(mesh_data_size), G_ALLOCATORS.main_allocator)
	defer common.arena_delete(mesh_data_arena)

	// Load metadata
	mesh_metadata: MeshAssetMetadata
	mesh_name := common.get_string(p_mesh_asset_name)

	{
		mesh_metadata_file_path := common.aprintf(
			temp_arena.allocator,
			"%s%s.metadata",
			G_MESH_ASSETS_DIR,
			mesh_name,
		)
		mesh_metadata_json, success := os.read_entire_file(
			mesh_metadata_file_path,
			context.temp_allocator,
		)
		if !success {
			log.warnf("Failed to load mesh '%s' - couldn't load metadata\n", mesh_name)
			return InvalidMeshAssetRef
		}
		err := json.unmarshal(mesh_metadata_json, &mesh_metadata, .JSON5, context.temp_allocator)
		if err != nil {
			log.warnf("Failed to load mesh '%s' - couldn't read metadata\n", mesh_name)
			return InvalidMeshAssetRef
		}
	}

	// Load mesh data
	mesh_data, success := os.read_entire_file(mesh_asset_path, mesh_data_arena.allocator)
	if success == false {
		log.warnf("Failed to load mesh '%s' - couldn't open file %s\n", mesh_name, mesh_asset_path)
		return InvalidMeshAssetRef
	}

	// Create renderer mesh
	mesh_resource_ref := renderer.allocate_mesh_ref(
		p_mesh_asset_name,
		u32(len(mesh_metadata.sub_meshes)),
	)
	mesh_resource_idx := renderer.get_mesh_idx(mesh_resource_ref)
	mesh_resource := &renderer.g_resources.meshes[mesh_resource_idx]

	mesh_data_offset := mesh_metadata.total_index_size

	mesh_resource.desc.position = common.slice_cast(
		glsl.vec3,
		mesh_data,
		mesh_data_offset,
		mesh_metadata.num_vertices,
	)

	mesh_data_offset += size_of(glsl.vec3) * mesh_metadata.num_vertices

	// Setup mesh flags, features and data pointer
	if .IndexedDraw in mesh_metadata.feature_flags {
		mesh_resource.desc.flags += {.Indexed}
		mesh_resource.desc.indices = common.slice_cast(
			u32,
			mesh_data,
			0,
			mesh_metadata.num_indices,
		)
	}

	if .Normal in mesh_metadata.feature_flags {

		mesh_resource.desc.normal = common.slice_cast(
			glsl.vec3,
			mesh_data,
			mesh_data_offset,
			mesh_metadata.num_vertices,
		)

		mesh_resource.desc.features += {.Normal}
		mesh_data_offset += size_of(glsl.vec3) * mesh_metadata.num_vertices
	}

	if .Tangent in mesh_metadata.feature_flags {
		mesh_resource.desc.tangent = common.slice_cast(
			glsl.vec3,
			mesh_data,
			mesh_data_offset,
			mesh_metadata.num_vertices,
		)

		mesh_resource.desc.features += {.Tangent}
		mesh_data_offset += size_of(glsl.vec3) * mesh_metadata.num_vertices
	}

	if .UV in mesh_metadata.feature_flags {
		mesh_resource.desc.uv = common.slice_cast(
			glsl.vec2,
			mesh_data,
			mesh_data_offset,
			mesh_metadata.num_vertices,
		)

		mesh_resource.desc.features += {.UV}
		mesh_data_offset += size_of(glsl.vec2) * mesh_metadata.num_vertices
	}

	// Setup submeshes information
	for sub_mesh_metadata, i in mesh_metadata.sub_meshes {

		material_asset_ref := material_asset_load(sub_mesh_metadata.material_asset_name)
		material_asset := material_asset_get(material_asset_ref)

		mesh_resource.desc.sub_meshes[i] = renderer.SubMesh {
			data_offset           = sub_mesh_metadata.data_offset,
			data_count            = sub_mesh_metadata.data_count,
			material_instance_ref = material_asset.material_instance_ref,
		}
	}

	// Create the mesh resource
	if renderer.create_mesh(mesh_resource_ref) == false {
		return InvalidMeshAssetRef
	}

	// Safe to do, as the data now has been uploaded to the staging buffer 
	// and memory  will be freed at the end of the function call
	mesh_resource.desc.position = nil
	mesh_resource.desc.normal = nil
	mesh_resource.desc.uv = nil
	mesh_resource.desc.tangent = nil
	mesh_resource.desc.indices = nil

	mesh_asset_ref := allocate_mesh_asset_ref(p_mesh_asset_name)
	mesh_asset := mesh_asset_get(mesh_asset_ref)
	mesh_asset.metadata = mesh_metadata
	mesh_asset.ref_count = 1
	mesh_asset.mesh_ref = mesh_resource_ref

	return mesh_asset_ref
}

//---------------------------------------------------------------------------//

mesh_asset_unload :: proc(p_mesh_asset_ref: MeshAssetRef) {
	mesh_asset := mesh_asset_get(p_mesh_asset_ref)
	mesh_asset.ref_count -= 1
	if mesh_asset.ref_count > 0 {
		return
	}
	renderer.destroy_mesh(mesh_asset.mesh_ref)
}

//---------------------------------------------------------------------------//

@(private = "file")
assimp_load_node :: proc(
	p_scene: ^assimp.Scene,
	p_node: ^assimp.Node,
	p_import_ctx: ^MeshImportContext,
) {

	for i in 0 ..< p_node.mNumMeshes {
		assimp_mesh := p_scene.mMeshes[p_node.mMeshes[i]]
		assimp_mesh_name := string(assimp_mesh.mName.data[:assimp_mesh.mName.length])

		assimp_material := p_scene.mMaterials[assimp_mesh.mMaterialIndex]

		// Create a new material asset for this submesh
		material_props := DefaultMaterialPropertiesAssetJSON {
			flags = 0,
		}
		material_asset_name := common.create_name(assimp_mesh_name)
		material_asset_ref := allocate_material_asset_ref(material_asset_name)
		material_asset := material_asset_get(material_asset_ref)
		material_asset.material_type_name = common.create_name("Default")

		if (material_asset_create(material_asset_ref) == false) {
			return
		}

		// Set default scalar values
		material_props.albedo = {1, 1, 1}
		material_props.normal = {0, 1, 0}
		material_props.roughness = 0.5
		material_props.metalness = 0
		material_props.occlusion = 1

		// Import all of the textures for this submesh and set it in the material
		assimp_material_import_texture(
			assimp_material,
			.AitexturetypeBaseColor,
			p_import_ctx.mesh_dir,
			&material_props.albedo_image_name,
			&material_props.flags,
			1 << 0,
		)

		assimp_material_import_texture(
			assimp_material,
			.AitexturetypeNormals,
			p_import_ctx.mesh_dir,
			&material_props.normal_image_name,
			&material_props.flags,
			1 << 1,
		)
		assimp_material_import_texture(
			assimp_material,
			.AitexturetypeDiffuseRoughness,
			p_import_ctx.mesh_dir,
			&material_props.roughness_image_name,
			&material_props.flags,
			1 << 2,
		)
		assimp_material_import_texture(
			assimp_material,
			.AitexturetypeMetalness,
			p_import_ctx.mesh_dir,
			&material_props.metalness_image_name,
			&material_props.flags,
			1 << 3,
		)
		assimp_material_import_texture(
			assimp_material,
			.AitexturetypeLightmap,
			p_import_ctx.mesh_dir,
			&material_props.occlusion_image_name,
			&material_props.flags,
			1 << 4,
		)

		// Save the newly created material asset
		material_asset_save_new_default(material_asset_ref, material_props)
		material_asset_unload(material_asset_ref)

		// Set the material for this submesh
		p_import_ctx.sub_meshes[p_import_ctx.current_sub_mesh].material_asset_name =
			material_asset_name

		// Load mesh data
		sub_mesh := &p_import_ctx.sub_meshes[p_import_ctx.current_sub_mesh]

		if .IndexedDraw in p_import_ctx.mesh_feature_flags {
			sub_mesh.data_count = assimp_mesh.mNumFaces * 3
			sub_mesh.data_offset = p_import_ctx.curr_idx

		} else {
			sub_mesh.data_count = assimp_mesh.mNumVertices
			sub_mesh.data_offset = p_import_ctx.curr_vtx
		}

		sub_mesh.vertex_offset = p_import_ctx.curr_vtx

		for j in 0 ..< assimp_mesh.mNumVertices {

			p_import_ctx.positions[p_import_ctx.curr_vtx] = {
				assimp_mesh.mVertices[j].x,
				assimp_mesh.mVertices[j].y,
				assimp_mesh.mVertices[j].z,
			}

			if .Normal in p_import_ctx.mesh_feature_flags {
				p_import_ctx.normals[p_import_ctx.curr_vtx] = {
					assimp_mesh.mNormals[j].x,
					assimp_mesh.mNormals[j].y,
					assimp_mesh.mNormals[j].z,
				}
			}

			if .Tangent in p_import_ctx.mesh_feature_flags {
				p_import_ctx.tangents[p_import_ctx.curr_vtx] = {
					assimp_mesh.mTangents[j].x,
					assimp_mesh.mTangents[j].y,
					assimp_mesh.mTangents[j].z,
				}
			}

			if .UV in p_import_ctx.mesh_feature_flags {
				p_import_ctx.uvs[p_import_ctx.curr_vtx] = {
					assimp_mesh.mTextureCoords[0][j].x,
					assimp_mesh.mTextureCoords[0][j].y,
				}
			}

			p_import_ctx.curr_vtx += 1
		}

		for j in 0 ..< assimp_mesh.mNumFaces {
			for k in 0 ..< assimp_mesh.mFaces[j].mNumIndices {
				idx := sub_mesh.vertex_offset + assimp_mesh.mFaces[j].mIndices[k]
				p_import_ctx.indices[p_import_ctx.curr_idx] = u32(idx)
				p_import_ctx.curr_idx += 1
			}
		}

		p_import_ctx.current_sub_mesh += 1
	}

	for i in 0 ..< p_node.mNumChildren {
		assimp_load_node(p_scene, p_node.mChildren[i], p_import_ctx)
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
assimp_material_import_texture :: proc(
	p_assimp_material: ^assimp.Material,
	p_assimp_texture_type: assimp.TextureType,
	p_mesh_dir: string,
	p_out_texture_name: ^string,
	p_out_flags: ^u32,
	p_texture_flag: u32,
) {
	texture_path: assimp.String
	assimp_get_material_texture(p_assimp_material, p_assimp_texture_type, &texture_path)

	if texture_path.length == 0 {
		return
	}

	texture_import_options := TextureAssetImportOptions {
		file_path = filepath.join(
			{p_mesh_dir, string(texture_path.data[:texture_path.length])},
			context.temp_allocator,
		),
	}

	if p_assimp_texture_type == .AitexturetypeNormals {
		texture_import_options.flags += {.IsNormalMap}
	}

	import_result := texture_asset_import(texture_import_options)
	if import_result.status != .Error {
		p_out_texture_name^ = common.get_string(import_result.name)
		p_out_flags^ |= p_texture_flag
	}
}

//---------------------------------------------------------------------------//

@(private = "file")
assimp_get_material_texture :: #force_inline proc(
	p_material: ^assimp.Material,
	p_texture_type: assimp.TextureType,
	p_path: ^assimp.String,
) -> assimp.Return {
	return assimp.get_material_texture(
		p_material,
		p_texture_type,
		0,
		p_path,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
	)
}

//---------------------------------------------------------------------------//
