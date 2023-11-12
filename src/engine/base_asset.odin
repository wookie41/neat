package engine

//---------------------------------------------------------------------------//

import "../common"
import "core:encoding/json"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:time"

//---------------------------------------------------------------------------//

AssetType :: enum {
	Texture,
	Mesh,
	Material,
}

//---------------------------------------------------------------------------//

AssetMetadataBase :: struct {
	name:    common.Name,
	uuid:    UUID,
	type:    AssetType,
	version: u32,
}

//---------------------------------------------------------------------------//

@(private = "file")
UUID_Union :: struct #raw_union {
	using _: struct #packed {
		time_low:                           u32,
		time_mid:                           u16,
		time_hi_and_version:                u16,
		clock_seq_hi_and_res_clock_seq_low: u16,
		node:                               [3]u16,
	},
	raw:     u128,
}

//---------------------------------------------------------------------------//

#assert(size_of(UUID_Union) == size_of(u128))
UUID :: u128

//---------------------------------------------------------------------------//

uuid_create :: proc(version: u16 = 0) -> UUID {
	return uuid_create_union(version).raw
}

//---------------------------------------------------------------------------//

@(private = "file")
uuid_create_union :: proc(version: u16 = 0) -> UUID_Union {
	// RFC 4122 - Loosely based on version 4.2
	v := version == 0 ? u16(rand.uint32()) : version // if no version passed in, generate a random one
	cs := u16(rand.uint32())
	n: [3]u16 = {u16(rand.uint32()), u16(rand.uint32()), u16(rand.uint32())}
	t := time.now()

	u: UUID_Union
	u.time_low = u32(t._nsec & 0x00000000ffffffff)
	u.time_mid = u16((t._nsec & 0x000000ffff000000) >> 24)
	u.time_hi_and_version = u16(u16(t._nsec >> 52) | v)
	u.clock_seq_hi_and_res_clock_seq_low = cs
	u.node = n

	return u
}

//---------------------------------------------------------------------------//

uuid_create_string :: proc(version: u16 = 0, allocator := context.allocator) -> string {
	using strings

	uuid := uuid_create_union(version)

	sb := builder_make(allocator)
	builder_grow(&sb, 38)
	defer builder_destroy(&sb)

	fmt.sbprintf(
		&sb,
		"{{%08x-%04x-%04x-%04x-%04x%04x%04x}",
		uuid.time_low,
		uuid.time_mid,
		uuid.time_hi_and_version,
		uuid.clock_seq_hi_and_res_clock_seq_low,
		uuid.node[0],
		uuid.node[1],
		uuid.node[2],
	)

	return to_string(sb)
}

//---------------------------------------------------------------------------//

AssetImportResultStatus :: enum u16 {
	Ok,
	Duplicate,
	Error,
}

//---------------------------------------------------------------------------//

AssetImportResult :: struct {
	name:   common.Name,
	status: AssetImportResultStatus,
}

//---------------------------------------------------------------------------//

AssetDatabaseEntry :: struct {
	uuid:      UUID,
	name:      string, // User readable name of the asset
	file_name: string `json:"fileName"`, // Name of the asset file inside assets dir
}

//---------------------------------------------------------------------------//

AssetDatabase :: struct {
	db_entries:   [dynamic]AssetDatabaseEntry,
	db_file_path: string,
}

//---------------------------------------------------------------------------//

asset_database_init :: proc(p_asset_database: ^AssetDatabase, p_db_file_path: string) {
	p_asset_database.db_file_path = p_db_file_path
	p_asset_database.db_entries = make([dynamic]AssetDatabaseEntry, G_ALLOCATORS.main_allocator)
}

//---------------------------------------------------------------------------//

asset_database_read :: proc(p_asset_database: ^AssetDatabase) -> bool {
	// Make sure that the database file is created
	if os.exists(p_asset_database.db_file_path) == false {
		f, err := os.open(p_asset_database.db_file_path, os.O_CREATE)
		assert(err == 0)
		_, err = os.write_string(f, "[]")
		assert(err == 0)
		os.close(f)
	}

	// Read the database file
	db_data, db_read_ok := os.read_entire_file(
		p_asset_database.db_file_path,
		context.temp_allocator,
	)
	if db_read_ok == false {
		return false
	}

	err := json.unmarshal(
		db_data,
		&p_asset_database.db_entries,
		json.DEFAULT_SPECIFICATION,
		G_ALLOCATORS.main_allocator,
	)

	if (err != nil) {
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

asset_database_save :: proc(p_asset_database: ^AssetDatabase) -> bool {
	json_data, err := json.marshal(
		p_asset_database.db_entries,
		json.Marshal_Options{spec = .JSON5, pretty = true},
		context.temp_allocator,
	)
	if err != nil {
		return false
	}
	defer delete(json_data, context.temp_allocator)
	if os.write_entire_file(p_asset_database.db_file_path, json_data) == false {
		return false
	}
	return true
}

//---------------------------------------------------------------------------//

asset_database_add :: proc(
	p_asset_database: ^AssetDatabase,
	p_new_entry: AssetDatabaseEntry,
	p_save: bool = false,
) {
	append(&p_asset_database.db_entries, p_new_entry)
	if (p_save) {
		asset_database_save(p_asset_database)
	}
}

//---------------------------------------------------------------------------//
