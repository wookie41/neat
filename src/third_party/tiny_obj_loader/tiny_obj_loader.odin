package tiny_obj_loader

foreign import "external/tiny_obj_loader.lib"

import _c "core:c"

TINOBJ_LOADER_C_H_ :: 1;
TINYOBJ_FLAG_TRIANGULATE :: 1;
TINYOBJ_INVALID_INDEX :: 2147483648;
TINYOBJ_SUCCESS :: 0;
TINYOBJ_ERROR_EMPTY :: -1;
TINYOBJ_ERROR_INVALID_PARAMETER :: -2;
TINYOBJ_ERROR_FILE_OPERATION :: -3;
TINYOBJ_MAX_FACES_PER_F_LINE :: 16;
TINYOBJ_MAX_FILEPATH :: 8192;
HASH_TABLE_ERROR :: 1;
HASH_TABLE_SUCCESS :: 0;
HASH_TABLE_DEFAULT_SIZE :: 10;

file_reader_callback :: #type proc "c" (ctx : rawptr, filename : cstring, is_mtl : _c.int, obj_filename : cstring, buf : ^cstring, len : ^_c.size_t);

CommandType :: enum i32 {
    CommandEmpty,
    CommandV,
    CommandVn,
    CommandVt,
    CommandF,
    CommandG,
    CommandO,
    CommandUsemtl,
    CommandMtllib,
};

tinyobj_material_t :: struct {
    name : cstring,
    ambient : [3]_c.float,
    diffuse : [3]_c.float,
    specular : [3]_c.float,
    transmittance : [3]_c.float,
    emission : [3]_c.float,
    shininess : _c.float,
    ior : _c.float,
    dissolve : _c.float,
    illum : _c.int,
    pad0 : _c.int,
    ambient_texname : cstring,
    diffuse_texname : cstring,
    specular_texname : cstring,
    specular_highlight_texname : cstring,
    bump_texname : cstring,
    displacement_texname : cstring,
    alpha_texname : cstring,
};

tinyobj_shape_t :: struct {
    name : cstring,
    face_offset : _c.uint,
    length : _c.uint,
};

tinyobj_vertex_index_t :: struct {
    v_idx : _c.int,
    vt_idx : _c.int,
    vn_idx : _c.int,
};

tinyobj_attrib_t :: struct {
    num_vertices : _c.uint,
    num_normals : _c.uint,
    num_texcoords : _c.uint,
    num_faces : _c.uint,
    num_face_num_verts : _c.uint,
    pad0 : _c.int,
    vertices : [^]_c.float,
    normals : [^]_c.float,
    texcoords : [^]_c.float,
    faces : [^]tinyobj_vertex_index_t,
    face_num_verts : ^_c.int,
    material_ids : ^_c.int,
};

hash_table_entry_t :: struct {
    hash : _c.ulong,
    filled : _c.int,
    pad0 : _c.int,
    value : _c.long,
    next : ^hash_table_entry_t,
};

hash_table_t :: struct {
    hashes : ^_c.ulong,
    entries : ^hash_table_entry_t,
    capacity : _c.size_t,
    n : _c.size_t,
};

LineInfo :: struct {
    pos : _c.size_t,
    len : _c.size_t,
};

Command :: struct {
    vx : _c.float,
    vy : _c.float,
    vz : _c.float,
    nx : _c.float,
    ny : _c.float,
    nz : _c.float,
    tx : _c.float,
    ty : _c.float,
    f : [16]tinyobj_vertex_index_t,
    num_f : _c.size_t,
    f_num_verts : [16]_c.int,
    num_f_num_verts : _c.size_t,
    group_name : cstring,
    group_name_len : _c.uint,
    pad0 : _c.int,
    object_name : cstring,
    object_name_len : _c.uint,
    pad1 : _c.int,
    material_name : cstring,
    material_name_len : _c.uint,
    pad2 : _c.int,
    mtllib_name : cstring,
    mtllib_name_len : _c.uint,
    type : CommandType,
};

@(default_calling_convention="c")
foreign tiny_obj_loader {

    @(link_name="tinyobj_parse_obj")
    parse_obj :: proc(attrib : ^tinyobj_attrib_t, shapes : ^[^]tinyobj_shape_t, num_shapes : ^_c.size_t, materials : ^[^]tinyobj_material_t, num_materials : ^_c.size_t, file_name : cstring, file_reader : file_reader_callback, ctx : rawptr, flags : _c.uint) -> _c.int ---;

    @(link_name="tinyobj_parse_mtl_file")
    parse_mtl_file :: proc(materials_out : ^^tinyobj_material_t, num_materials_out : ^_c.size_t, filename : cstring, obj_filename : cstring, file_reader : file_reader_callback, ctx : rawptr) -> _c.int ---;

    @(link_name="tinyobj_attrib_init")
    attrib_init :: proc(attrib : ^tinyobj_attrib_t) ---;

    @(link_name="tinyobj_attrib_free")
    attrib_free :: proc(attrib : ^tinyobj_attrib_t) ---;

    @(link_name="tinyobj_shapes_free")
    shapes_free :: proc(shapes : ^tinyobj_shape_t, num_shapes : _c.size_t) ---;

    @(link_name="tinyobj_materials_free")
    materials_free :: proc(materials : ^tinyobj_material_t, num_materials : _c.size_t) ---;

    @(link_name="skip_space")
    skip_space :: proc(token : ^cstring) ---;

    @(link_name="skip_space_and_cr")
    skip_space_and_cr :: proc(token : ^cstring) ---;

    @(link_name="until_space")
    until_space :: proc(token : cstring) -> _c.int ---;

    @(link_name="length_until_newline")
    length_until_newline :: proc(token : cstring, n : _c.size_t) -> _c.size_t ---;

    @(link_name="length_until_line_feed")
    length_until_line_feed :: proc(token : cstring, n : _c.size_t) -> _c.size_t ---;

    @(link_name="my_atoi")
    my_atoi :: proc(c : cstring) -> _c.int ---;

    @(link_name="fixIndex")
    fix_index :: proc(idx : _c.int, n : _c.size_t) -> _c.int ---;

    @(link_name="parseRawTriple")
    parse_raw_triple :: proc(token : ^cstring) -> tinyobj_vertex_index_t ---;

    @(link_name="parseInt")
    parse_int :: proc(token : ^cstring) -> _c.int ---;

    @(link_name="tryParseDouble")
    try_parse_double :: proc(s : cstring, s_end : cstring, result : ^_c.double) -> _c.int ---;

    @(link_name="parseFloat")
    parse_float :: proc(token : ^cstring) -> _c.float ---;

    @(link_name="parseFloat2")
    parse_float2 :: proc(x : ^_c.float, y : ^_c.float, token : ^cstring) ---;

    @(link_name="parseFloat3")
    parse_float3 :: proc(x : ^_c.float, y : ^_c.float, z : ^_c.float, token : ^cstring) ---;

    @(link_name="my_strnlen")
    my_strnlen :: proc(s : cstring, n : _c.size_t) -> _c.size_t ---;

    @(link_name="my_strdup")
    my_strdup :: proc(s : cstring, max_length : _c.size_t) -> cstring ---;

    @(link_name="my_strndup")
    my_strndup :: proc(s : cstring, len : _c.size_t) -> cstring ---;

    // @(link_name="dynamic_fgets")
    // dynamic_fgets :: proc(buf : ^cstring, size : ^_c.size_t, file : ^FILE) -> cstring ---;

    @(link_name="initMaterial")
    init_material :: proc(material : ^tinyobj_material_t) ---;

    @(link_name="hash_djb2")
    hash_djb2 :: proc(str : ^_c.uchar) -> _c.ulong ---;

    @(link_name="create_hash_table")
    create_hash_table :: proc(start_capacity : _c.size_t, hash_table : ^hash_table_t) ---;

    @(link_name="destroy_hash_table")
    destroy_hash_table :: proc(hash_table : ^hash_table_t) ---;

    @(link_name="hash_table_insert_value")
    hash_table_insert_value :: proc(hash : _c.ulong, value : _c.long, hash_table : ^hash_table_t) -> _c.int ---;

    @(link_name="hash_table_insert")
    hash_table_insert :: proc(hash : _c.ulong, value : _c.long, hash_table : ^hash_table_t) -> _c.int ---;

    @(link_name="hash_table_find")
    hash_table_find :: proc(hash : _c.ulong, hash_table : ^hash_table_t) -> ^hash_table_entry_t ---;

    @(link_name="hash_table_maybe_grow")
    hash_table_maybe_grow :: proc(new_n : _c.size_t, hash_table : ^hash_table_t) ---;

    @(link_name="hash_table_exists")
    hash_table_exists :: proc(name : cstring, hash_table : ^hash_table_t) -> _c.int ---;

    @(link_name="hash_table_set")
    hash_table_set :: proc(name : cstring, val : _c.size_t, hash_table : ^hash_table_t) ---;

    @(link_name="hash_table_get")
    hash_table_get :: proc(name : cstring, hash_table : ^hash_table_t) -> _c.long ---;

    @(link_name="tinyobj_material_add")
    material_add :: proc(prev : ^tinyobj_material_t, num_materials : _c.size_t, new_mat : ^tinyobj_material_t) -> ^tinyobj_material_t ---;

    @(link_name="is_line_ending")
    is_line_ending :: proc(p : cstring, i : _c.size_t, end_i : _c.size_t) -> _c.int ---;

    @(link_name="get_line_infos")
    get_line_infos :: proc(buf : cstring, buf_len : _c.size_t, line_infos : ^^LineInfo, num_lines : ^_c.size_t) -> _c.int ---;

    @(link_name="tinyobj_parse_and_index_mtl_file")
    parse_and_index_mtl_file :: proc(materials_out : ^^tinyobj_material_t, num_materials_out : ^_c.size_t, mtl_filename : cstring, obj_filename : cstring, file_reader : file_reader_callback, ctx : rawptr, material_table : ^hash_table_t) -> _c.int ---;

    @(link_name="parseLine")
    parse_line :: proc(command : ^Command, p : cstring, p_len : _c.size_t, triangulate : _c.int) -> _c.int ---;

    @(link_name="basename_len")
    basename_len :: proc(filename : cstring, filename_length : _c.size_t) -> _c.size_t ---;

    @(link_name="generate_mtl_filename")
    generate_mtl_filename :: proc(obj_filename : cstring, obj_filename_length : _c.size_t, mtllib_name : cstring, mtllib_name_length : _c.size_t) -> cstring ---;

}
