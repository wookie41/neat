package engine

//---------------------------------------------------------------------------//

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
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
	vertex_offset:       u32 `json:"vertexOffset"`,
	vertex_count:        u32 `json:"vertexCount"`,
	index_offset:        u32 `json:"indexOffset"`,
	index_count:         u32 `json:"indexCount"`,
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

	asset_database_init(&INTERNAL.mesh_database, G_MESH_DB_PATH)
	asset_database_read(&INTERNAL.mesh_database)
}

//---------------------------------------------------------------------------//

@(private = "file")
SubMesh :: struct {
	vertex_offset:       u32,
	vertex_count:        u32,
	index_offset:        u32,
	index_count:         u32,
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
	mesh_name:          string,
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
	common.temp_arena_init(&temp_arena, common.KILOBYTE * 128)
	defer common.arena_delete(temp_arena)

	mesh_asset_name := filepath.short_stem(filepath.base(p_import_options.file_path))
	mesh_file_path := strings.clone_to_cstring(p_import_options.file_path, temp_arena.allocator)

	// Check if the mesh already exits
	mesh_asset_file_name := strings.concatenate({mesh_asset_name, ".bin"}, temp_arena.allocator)
	mesh_asset_path := filepath.join(
		{G_MESH_ASSETS_DIR, mesh_asset_file_name},
		temp_arena.allocator,
	)
	if os.exists(mesh_asset_path) {
		return {status = .Duplicate, name = common.create_name(mesh_asset_name)}
	}

	scene := assimp.import_file(
		mesh_file_path,
		{
			.CalcTangentSpace,
			.FlipUVs,
			.JoinIdenticalVertices,
			.Triangulate,
			.ImproveCacheLocality,
			.FindDegenerates,
			.OptimizeMeshes,
			.GenSmoothNormals,
		},
	)
	if scene == nil ||
	   (scene.mFlags & assimp.SCENE_FLAGS_INCOMPLETE) > 0 ||
	   scene.mRootNode == nil {
		return AssetImportResult{status = .Error}
	}
	defer assimp.release_import(scene)

	mesh_import_ctx := MeshImportContext {
		curr_idx  = 0,
		curr_vtx  = 0,
		mesh_dir  = filepath.dir(p_import_options.file_path, temp_arena.allocator),
		mesh_name = mesh_asset_name,
	}

	log.infof("Importing mesh '%s'\n", mesh_asset_name)

	// Calculate the number of vertices and indices
	num_vertices: u32 = 0
	num_indices: u32 = 0

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
	assimp_load_node(scene, scene.mRootNode, &mesh_import_ctx, glsl.identity(glsl.mat4x4))

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
			vertex_offset       = sub_mesh.vertex_offset,
			vertex_count        = sub_mesh.vertex_count,
			index_offset        = sub_mesh.index_offset,
			index_count         = sub_mesh.index_count,
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
	defer os.close(fd)

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
mesh_asset_load_by_name :: proc(p_mesh_asset_name: common.Name) -> (ret_mesh_ref: MeshAssetRef) {

	// Check if it's already loaded
	{
		mesh_asset_ref := common.ref_find_by_name(&G_MESH_ASSET_REF_ARRAY, p_mesh_asset_name)
		if mesh_asset_ref != InvalidMeshAssetRef {
			mesh_asset_get(mesh_asset_ref).ref_count += 1
			return mesh_asset_ref
		}
	}

	log.infof("Loading mesh '%s'\n", common.get_string(p_mesh_asset_name))

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena, common.MEGABYTE)
	defer common.arena_delete(temp_arena)

	mesh_asset_path := asset_create_path(
		G_MESH_ASSETS_DIR,
		p_mesh_asset_name,
		"bin",
		temp_arena.allocator,
	)

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
			temp_arena.allocator,
		)
		if !success {
			log.warnf("Failed to load mesh '%s' - couldn't load metadata\n", mesh_name)
			return InvalidMeshAssetRef
		}
		err := json.unmarshal(mesh_metadata_json, &mesh_metadata, .JSON5, temp_arena.allocator)
		if err != nil {
			log.warnf("Failed to load mesh '%s' - couldn't read metadata\n", mesh_name)
			return InvalidMeshAssetRef
		}
	}

	// Create renderer mesh
	mesh_resource_ref := renderer.mesh_allocate(
		p_mesh_asset_name,
		u32(len(mesh_metadata.sub_meshes)),
	)
	mesh_resource_idx := renderer.mesh_get_idx(mesh_resource_ref)
	mesh_resource := &renderer.g_resources.meshes[mesh_resource_idx]
	mesh_resource.desc.data_allocator = G_ALLOCATORS.main_allocator

	// Load mesh data
	file_mapping, mapping_success := common.mmap_file(mesh_asset_path)
	if mapping_success == false {
		log.warnf(
			"Failed to load mesh '%s' - couldn't mmap file\n",
			common.get_string(p_mesh_asset_name),
		)
		return InvalidMeshAssetRef
	}

	mesh_resource.desc.file_mapping = file_mapping

	// Setup index pointer
	current_data_ptr := (^byte)(file_mapping.mapped_ptr)
	if .IndexedDraw in mesh_metadata.feature_flags {
		mesh_resource.desc.flags += {.Indexed}
		mesh_resource.desc.indices = slice.from_ptr(
			(^u32)(current_data_ptr),
			int(mesh_metadata.num_indices),
		)

		current_data_ptr = mem.ptr_offset(current_data_ptr, (mesh_metadata.total_index_size))
	}

	// Setup positions pointer
	mesh_resource.desc.position = slice.from_ptr(
		(^glsl.vec3)(current_data_ptr),
		int(mesh_metadata.num_vertices),
	)

	current_data_ptr = mem.ptr_offset(
		current_data_ptr,
		size_of(glsl.vec3) * (mesh_metadata.num_vertices),
	)


	// Setup normals pointer
	if .Normal in mesh_metadata.feature_flags {
		mesh_resource.desc.features += {.Normal}

		mesh_resource.desc.normal = slice.from_ptr(
			(^glsl.vec3)(current_data_ptr),
			int(mesh_metadata.num_vertices),
		)

		current_data_ptr = mem.ptr_offset(
			current_data_ptr,
			size_of(glsl.vec3) * (mesh_metadata.num_vertices),
		)
	}

	// Setup tangents pointer
	if .Tangent in mesh_metadata.feature_flags {
		mesh_resource.desc.features += {.Tangent}

		mesh_resource.desc.tangent = slice.from_ptr(
			(^glsl.vec3)(current_data_ptr),
			int(mesh_metadata.num_vertices),
		)

		current_data_ptr = mem.ptr_offset(
			current_data_ptr,
			size_of(glsl.vec3) * (mesh_metadata.num_vertices),
		)
	}

	// Setup uvs pointer
	if .UV in mesh_metadata.feature_flags {
		mesh_resource.desc.features += {.UV}

		mesh_resource.desc.uv = slice.from_ptr(
			(^glsl.vec2)(current_data_ptr),
			int(mesh_metadata.num_vertices),
		)

		current_data_ptr = mem.ptr_offset(
			current_data_ptr,
			size_of(glsl.vec2) * (mesh_metadata.num_vertices),
		)
	}


	// Setup submeshes information
	for sub_mesh_metadata, i in mesh_metadata.sub_meshes {

		material_asset_ref := material_asset_load(sub_mesh_metadata.material_asset_name)
		assert(material_asset_ref != InvalidMaterialAssetRef)
		material_asset := material_asset_get(material_asset_ref)

		mesh_resource.desc.sub_meshes[i] = renderer.SubMesh {
			vertex_offset         = sub_mesh_metadata.vertex_offset,
			vertex_count          = sub_mesh_metadata.vertex_count,
			index_offset          = sub_mesh_metadata.index_offset,
			index_count           = sub_mesh_metadata.index_count,
			material_instance_ref = material_asset.material_instance_ref,
		}
	}

	// Create the mesh resource
	if renderer.mesh_create(mesh_resource_ref) == false {
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
	renderer.mesh_destroy(mesh_asset.mesh_ref)
}

//---------------------------------------------------------------------------//

@(private = "file")
assimp_load_node :: proc(
	p_scene: ^assimp.Scene,
	p_node: ^assimp.Node,
	p_import_ctx: ^MeshImportContext,
	p_parent_transform: glsl.mat4x4,
) {

	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	node_transform := p_parent_transform * glsl.mat4x4{
		p_node.mTransformation.a1, p_node.mTransformation.a2, p_node.mTransformation.a3, p_node.mTransformation.a4,
		p_node.mTransformation.b1, p_node.mTransformation.b2, p_node.mTransformation.b3, p_node.mTransformation.b4,
		p_node.mTransformation.c1, p_node.mTransformation.c2, p_node.mTransformation.c3, p_node.mTransformation.c4,
		p_node.mTransformation.d1, p_node.mTransformation.d2, p_node.mTransformation.d3, p_node.mTransformation.d4,
	}

	for i in 0 ..< p_node.mNumMeshes {
		assimp_mesh := p_scene.mMeshes[p_node.mMeshes[i]]
		assimp_material := p_scene.mMaterials[assimp_mesh.mMaterialIndex]

		assimp_material_name: assimp.String
		assimp.get_material_string(
			assimp_material,
			assimp.MATKEY_NAME,
			0,
			0,
			&assimp_material_name,
		)
		material_name := string(assimp_material_name.data[:assimp_material_name.length])
		if assimp_material_name.length == 0 {
			buff: [64]byte
			material_idx := strconv.write_int(buff[:], i64(p_import_ctx.current_sub_mesh), 10)
			material_name = strings.clone(material_idx, temp_arena.allocator)
		}

		material_name = strings.concatenate(
			{p_import_ctx.mesh_name, "_", material_name},
			temp_arena.allocator,
		)

		// Create a new material asset for this submesh
		material_props := MaterialPropertiesAssetJSON {
			flags = 0,
		}
		material_asset_name := common.create_name(material_name)
		material_asset_ref := allocate_material_asset_ref(material_asset_name)
		material_asset := material_asset_get(material_asset_ref)
		material_asset.material_type_name = common.create_name("OpaquePBR")

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
		material_asset_save_new(material_asset_ref, material_props)
		material_asset_unload(material_asset_ref)

		// Set the material for this submesh
		p_import_ctx.sub_meshes[p_import_ctx.current_sub_mesh].material_asset_name =
			material_asset_name

		// Load mesh data
		sub_mesh := &p_import_ctx.sub_meshes[p_import_ctx.current_sub_mesh]

		sub_mesh.vertex_count = assimp_mesh.mNumVertices
		sub_mesh.vertex_offset = p_import_ctx.curr_vtx
		sub_mesh.index_count = assimp_mesh.mNumFaces * 3
		sub_mesh.index_offset = p_import_ctx.curr_idx

		for j in 0 ..< assimp_mesh.mNumVertices {

			p_import_ctx.positions[p_import_ctx.curr_vtx] = {
				assimp_mesh.mVertices[j].x,
				assimp_mesh.mVertices[j].y,
				assimp_mesh.mVertices[j].z,
			}
			p_import_ctx.positions[p_import_ctx.curr_vtx] = (node_transform * glsl.vec4{
				p_import_ctx.positions[p_import_ctx.curr_vtx].x,
				p_import_ctx.positions[p_import_ctx.curr_vtx].y,
				p_import_ctx.positions[p_import_ctx.curr_vtx].z,
				1}).xyz

			if assimp_mesh.mNormals != nil {
				p_import_ctx.normals[p_import_ctx.curr_vtx] = {
					assimp_mesh.mNormals[j].x,
					assimp_mesh.mNormals[j].y,
					assimp_mesh.mNormals[j].z,
				}
			} else {
				p_import_ctx.normals[p_import_ctx.curr_vtx] = {0, 0, 0}
			}

			if assimp_mesh.mTangents != nil {

				normal := p_import_ctx.normals[p_import_ctx.curr_vtx]

				tangent := glsl.vec3{
					assimp_mesh.mTangents[j].x,
					assimp_mesh.mTangents[j].y,
					assimp_mesh.mTangents[j].z,
				}

				bitangent := glsl.vec3{
					assimp_mesh.mBitangents[j].x,
					assimp_mesh.mBitangents[j].y,
					assimp_mesh.mBitangents[j].z,
				}

				// Make sure normal and tangent orthonormal
				tangent = glsl.normalize(tangent - glsl.dot(tangent, normal) * normal)

				// Make sure the basis is right-handed
				if glsl.dot(glsl.cross(normal, tangent), bitangent) < 0 {
					p_import_ctx.tangents[p_import_ctx.curr_vtx] = -tangent
				} else {
					p_import_ctx.tangents[p_import_ctx.curr_vtx] = tangent
				}

			} else {
				p_import_ctx.tangents[p_import_ctx.curr_vtx] = {0, 0, 0}
			}

			if assimp_mesh.mTextureCoords[0] != nil {
				p_import_ctx.uvs[p_import_ctx.curr_vtx] = {
					assimp_mesh.mTextureCoords[0][j].x,
					assimp_mesh.mTextureCoords[0][j].y,
				}
			} else {
				p_import_ctx.uvs[p_import_ctx.curr_vtx] = {0, 0}
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
		assimp_load_node(p_scene, p_node.mChildren[i], p_import_ctx, node_transform)
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
	temp_arena: common.Arena
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	texture_path: assimp.String
	assimp_get_material_texture(p_assimp_material, p_assimp_texture_type, &texture_path)

	if texture_path.length == 0 {
		return
	}

	texture_file_path := string(texture_path.data[:texture_path.length])
	if filepath.is_abs(texture_file_path) == false {
		texture_file_path = filepath.join({p_mesh_dir, texture_file_path}, temp_arena.allocator)
	}

	texture_import_options := TextureAssetImportOptions {
		file_path = texture_file_path,
	}

	if p_assimp_texture_type == .AitexturetypeBaseColor{
		texture_import_options.flags += {.IsColor}
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
