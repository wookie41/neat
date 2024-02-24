package renderer

//---------------------------------------------------------------------------//

import "core:c"
import "core:math/linalg/glsl"
import "core:mem"

import "../common"

//---------------------------------------------------------------------------//

@(private = "file")
G_IMAGE_REF_ARRAY: common.RefArray(ImageResource)

//---------------------------------------------------------------------------//

ImageRef :: common.Ref(ImageResource)

//---------------------------------------------------------------------------//

InvalidImageRef := ImageRef {
	ref = c.UINT32_MAX,
}

//---------------------------------------------------------------------------//

ImageAspectFlagBits :: enum u8 {
	Color,
	Depth,
	Stencil,
}

//---------------------------------------------------------------------------//

ImageAspectFlags :: distinct bit_set[ImageAspectFlagBits;u8]

//---------------------------------------------------------------------------//

G_IMAGE_TYPE_NAME_MAPPING := map[string]ImageType {
	"2D" = .OneDimensional,
	"3D" = .ThreeDimensional,
}

//---------------------------------------------------------------------------//

ImageType :: enum u8 {
	OneDimensional,
	TwoDimensional,
	ThreeDimensional,
}

//---------------------------------------------------------------------------//

@(private)
G_RESOLUTION_NAME_MAPPING := map[string]Resolution {
	"Full"    = .Full,
	"Half"    = .Half,
	"Quarter" = .Quarter,
}

//---------------------------------------------------------------------------//

Resolution :: enum u8 {
	Full,
	Half,
	Quarter,
}

//---------------------------------------------------------------------------//

@(private)
G_IMAGE_FORMAT_NAME_MAPPING := map[string]ImageFormat {
	"Depth32SFloat" = .Depth32SFloat,
	"R8UNorm"       = .R8UNorm,
	"R32UInt"       = .R32UInt,
	"R32Int"        = .R32Int,
	"R32SFloat"     = .R32SFloat,
	"RG8UNorm"      = .RG8UNorm,
	"RG32UInt"      = .RG32UInt,
	"RG32Int"       = .RG32Int,
	"RG32SFloat"    = .RG32SFloat,
	"RGB8UNorm"     = .RGB8UNorm,
	"RGB32UInt"     = .RGB32UInt,
	"RGB32Int"      = .RGB32Int,
	"RGB32SFloat"   = .RGB32SFloat,
	"RGBA8UNorm"    = .RGBA8UNorm,
	"RGBA16SNorm"   = .RGBA16SNorm,
	"RGBA32UInt"    = .RGBA32UInt,
	"RGBA32Int"     = .RGBA32Int,
	"RGBA32SFloat"  = .RGBA32SFloat,
	"RGBA8_SRGB"    = .RGBA8_SRGB,
	"BGRA8_SRGB"    = .BGRA8_SRGB,
	"BGRA8_SRGB"    = .BGRA8_SRGB,
}

//---------------------------------------------------------------------------//

ImageFormat :: enum u16 {
	//---------------------//
	DepthFormatsStart,

	//---------------------//
	DepthStencilFormatsStart,
	DepthStencilFormatsEnd,
	//---------------------//
	Depth32SFloat,
	DepthFormatsEnd,

	//---------------------//
	ColorFormatsStart,
	RFormatsStart,
	R32UInt,
	R32Int,
	R32SFloat,
	RFormatsEnd,
	R8UNorm,
	RGFormatsStart,
	RG8UNorm,
	RG32UInt,
	RG32Int,
	RG32SFloat,
	RGFormatsEnd,
	RGBFormatsStart,
	RGB8UNorm,
	RGB32UInt,
	RGB32Int,
	RGB32SFloat,
	RGBFormatsEnd,
	RGBAFormatsStart,
	RGBA8UNorm,
	RGBA32UInt,
	RGBA32Int,
	RGBA32SFloat,
	R11G11B10,
	RGBA16SNorm,
	RGBAFormatsEnd,
	SRGB_FormatsStart,
	RGBA8_SRGB,
	BGRA8_SRGB,
	SRGB_FormatsEnd,
	ColorFormatsEnd,
	//---------------------//
	CompressedFormatsStart,
	BC1_RGB_UNorm,
	BC1_RGB_SRGB,
	BC1_RGBA_UNorm,
	BC1_RGBA_SRGB,
	BC2_UNorm,
	BC2_SRGB,
	BC3_UNorm,
	BC3_SRGB,
	BC4_UNorm,
	BC4_SNorm,
	BC5_UNorm,
	BC5_SNorm,
	BC6H_UFloat,
	BC6H_SFloat,
	BC7_UNorm,
	BC7_SRGB,
	CompressedFormatsEnd,
	//---------------------//
}

//---------------------------------------------------------------------------//

ImageDescFlagBits :: enum u8 {
	Storage,
	Sampled,
	SwapImage,
	AddToBindlessArray,
}
ImageDescFlags :: distinct bit_set[ImageDescFlagBits;u8]


//---------------------------------------------------------------------------//

ImageFlagBits :: enum u8 {}
ImageFlags :: distinct bit_set[ImageFlagBits;u8]

//---------------------------------------------------------------------------//

ImageSampleFlagBits :: enum u8 {
	_1,
	_2,
	_4,
	_8,
	_16,
	_32,
	_64,
}
ImageSampleCountFlags :: distinct bit_set[ImageSampleFlagBits;u8]

//---------------------------------------------------------------------------//

ImageUsage :: enum u8 {
	Undefined,
	SampledImage,
	General,
	RenderTarget,
}

//---------------------------------------------------------------------------//

ImageDesc :: struct {
	name:               common.Name,
	type:               ImageType,
	format:             ImageFormat,
	mip_count:          u8,
	dimensions:         glsl.uvec3,
	flags:              ImageDescFlags,
	sample_count_flags: ImageSampleCountFlags,
	block_size:         u8, // size in bytes of a single block 4x4 for compressed textures
	data_per_mip:       [][]byte,
	file_mapping:       common.FileMemoryMapping,
	mip_data_allocator: mem.Allocator,
}

//---------------------------------------------------------------------------//

ImageResource :: struct {
	desc:             ImageDesc,
	flags:            ImageFlags,
	bindless_idx:     u32,
	loaded_mips_mask: u16, // mip 0 is the first bit
}

//---------------------------------------------------------------------------//

@(private = "file")
INTERNAL: struct {
	next_bindless_idx:                 u32,
	free_bindless_indices:             [dynamic]u32,
	image_uploads_in_progress:         [dynamic]ImageUploadInfo,
	staging_buffer_ref:                BufferRef,
	staging_buffer_offset:             u32,
	staging_buffer_single_region_size: u32,
}

//---------------------------------------------------------------------------//

SamplerType :: enum {
	NearestClampToEdge,
	NearestClampToBorder,
	NearestRepeat,
	LinearClampToEdge,
	LinearClampToBorder,
	LinearRepeat,
}

//---------------------------------------------------------------------------//

@(private)
SamplerNames := []string{
	"NearestClampToEdge",
	"NearestClampToBorder",
	"NearestRepeat",
	"LinearClampToEdge",
	"LinearClampToBorder",
	"LinearRepeat",
}

//---------------------------------------------------------------------------//

@(private)
ImageUploadInfo :: struct {
	image_ref:                    ImageRef,
	current_mip:                  u8,
	single_upload_size_in_texels: glsl.uvec2,
	mip_offset_in_texels:         glsl.uvec2,
	is_initialized:               bool,
}

//---------------------------------------------------------------------------//

@(private)
ImageMipRegionCopy :: struct {
	offset:                glsl.uvec2,
	staging_buffer_offset: u32,
}

//---------------------------------------------------------------------------//

@(private)
init_images :: proc() -> bool {
	G_IMAGE_REF_ARRAY = common.ref_array_create(
		ImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.main_allocator,
	)
	g_resources.images = make_soa(
		#soa[]ImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)
	g_resources.backend_images = make_soa(
		#soa[]BackendImageResource,
		MAX_IMAGES,
		G_RENDERER_ALLOCATORS.resource_allocator,
	)

	INTERNAL.next_bindless_idx = 0
	INTERNAL.free_bindless_indices = make([dynamic]u32, G_RENDERER_ALLOCATORS.main_allocator)
	INTERNAL.image_uploads_in_progress = make([dynamic]ImageUploadInfo, get_frame_allocator())

	// Create the staging buffer for image uploads
	{
		INTERNAL.staging_buffer_offset = 0
		INTERNAL.staging_buffer_single_region_size = common.MEGABYTE * 8
		INTERNAL.staging_buffer_ref = allocate_buffer_ref(common.create_name("ImageStagingBuffer"))

		staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer_ref)]
		staging_buffer.desc.size =
			INTERNAL.staging_buffer_single_region_size * G_RENDERER.num_frames_in_flight
		staging_buffer.desc.flags = {.HostWrite, .Mapped}
		staging_buffer.desc.usage = {.TransferSrc}

		create_buffer(INTERNAL.staging_buffer_ref) or_return
	}

	backend_init_images()

	// Create a default image that we'll use when a texture is missing
	{
		G_RENDERER.default_image_ref = allocate_image_ref(common.create_name("DefaultImage"))
		default_image := &g_resources.images[get_image_idx(G_RENDERER.default_image_ref)]

		default_image.desc.type = .TwoDimensional
		default_image.desc.dimensions = glsl.uvec3{4, 4, 1}
		default_image.desc.flags = {.Sampled, .AddToBindlessArray}
		default_image.desc.sample_count_flags = {._1}
		default_image.desc.format = .BC1_RGB_UNorm
		default_image.desc.mip_count = 1

		create_image(G_RENDERER.default_image_ref)
	}

	return true
}

//---------------------------------------------------------------------------//

@(private)
image_upload_begin_frame :: proc() {
	INTERNAL.staging_buffer_offset = 0
}

//---------------------------------------------------------------------------//

allocate_image_ref :: proc(p_name: common.Name) -> ImageRef {
	ref := ImageRef(common.ref_create(ImageResource, &G_IMAGE_REF_ARRAY, p_name))
	reset_image_ref(ref)
	image := &g_resources.images[get_image_idx(ref)]
	image.desc.name = p_name
	return ref
}

//---------------------------------------------------------------------------//

reset_image_ref :: proc(p_image_ref: ImageRef) {
	image := &g_resources.images[get_image_idx(p_image_ref)]
	backend_image := &g_resources.backend_images[get_image_idx(p_image_ref)]
	image^ = ImageResource{}
	backend_image^ = BackendImageResource{}
}

//---------------------------------------------------------------------------//

free_image_ref :: proc(p_ref: ImageRef) {
	common.ref_free(&G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

/** Helper method to create image that can later be used as a sampled image inside a shader */
create_texture_image :: proc(p_ref: ImageRef) -> bool {

	image := &g_resources.images[get_image_idx(p_ref)]
	image.bindless_idx = image_allocate_new_bindless_array_entry()
	// 3D texture loading not supported right now
	assert(image.desc.type == .TwoDimensional)

	assert(
		(image.desc.format > .ColorFormatsStart && image.desc.format < .ColorFormatsEnd) ||
		(image.desc.format > .CompressedFormatsStart && image.desc.format < .CompressedFormatsEnd),
	)

	// the loaded mips bitmask is 16 bit, but 2^15x2^15 should be enough for the texture
	assert(image.desc.mip_count <= 16)

	if backend_create_texture_image(p_ref) == false {
		append(&INTERNAL.free_bindless_indices, image.bindless_idx)
		common.ref_free(&G_IMAGE_REF_ARRAY, p_ref)
		return false
	}

	// Queue data copy for this texture
	image_upload_info := ImageUploadInfo {
		image_ref = p_ref,
		current_mip = image.desc.mip_count - 1,
		single_upload_size_in_texels = calculate_image_upload_size(
			image.desc.dimensions,
			image.desc.mip_count - 1,
		),
		mip_offset_in_texels = {0, 0},
		is_initialized = false,
	}
	append(&INTERNAL.image_uploads_in_progress, image_upload_info)

	return true
}

create_image :: proc(p_image_ref: ImageRef) -> bool {

	image := &g_resources.images[get_image_idx(p_image_ref)]

	if .AddToBindlessArray in image.desc.flags {
		image.bindless_idx = image_allocate_new_bindless_array_entry()
	}

	// the loaded mips bitmask is 16 bit, but 2^15x2^15 should be enough for the texture
	assert(image.desc.mip_count <= 16)

	if backend_create_image(p_image_ref) == false {
		append(&INTERNAL.free_bindless_indices, image.bindless_idx)

		common.ref_free(&G_IMAGE_REF_ARRAY, p_image_ref)
		return false
	}

	return true
}

//---------------------------------------------------------------------------//

get_image_idx :: #force_inline proc(p_ref: ImageRef) -> u32 {
	return common.ref_get_idx(&G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

create_swap_images :: proc() {
	backend_create_swap_images()
}

//---------------------------------------------------------------------------//

destroy_image :: proc(p_ref: ImageRef) {
	image := &g_resources.images[get_image_idx(p_ref)]
	if image.bindless_idx != c.UINT32_MAX {
		append(&INTERNAL.free_bindless_indices, image.bindless_idx)
	}
	backend_destroy_image(p_ref)
	common.ref_free(&G_IMAGE_REF_ARRAY, p_ref)
}

//---------------------------------------------------------------------------//

batch_update_bindless_array_entries :: proc() {
	backend_batch_update_bindless_array_entries()
}

//---------------------------------------------------------------------------//

find_image :: proc {
	find_image_by_name,
	find_image_by_str,
}

//---------------------------------------------------------------------------//

find_image_by_name :: proc(p_name: common.Name) -> ImageRef {
	ref := common.ref_find_by_name(&G_IMAGE_REF_ARRAY, p_name)
	if ref == InvalidImageRef {
		return InvalidImageRef
	}
	return ImageRef(ref)
}

//--------------------------------------------------------------------------//

find_image_by_str :: proc(p_str: string) -> ImageRef {
	return find_image_by_name(common.create_name(p_str))
}

//--------------------------------------------------------------------------//

@(private)
image_upload_progress_copies :: proc() {
	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena, common.KILOBYTE * 256)
	defer common.arena_delete(temp_arena)

	temp_arena2 := common.Arena{}
	common.temp_arena_init(&temp_arena2, common.KILOBYTE * 256)
	defer common.arena_delete(temp_arena2)

	surviving_uploads := make([dynamic]ImageUploadInfo, temp_arena.allocator)
	current_uploads := INTERNAL.image_uploads_in_progress

	arenas := []common.Arena{temp_arena2, temp_arena}
	arena_idx := 0

	for try_progress_image_copies(current_uploads, &surviving_uploads) {
		current_uploads = surviving_uploads

		common.arena_reset(arenas[arena_idx])
		surviving_uploads = make([dynamic]ImageUploadInfo, arenas[arena_idx].allocator)

		arena_idx = (arena_idx + 1) % 2
	}

	INTERNAL.image_uploads_in_progress = make(
		[dynamic]ImageUploadInfo,
		len(surviving_uploads),
		get_next_frame_allocator(),
	)

	copy(INTERNAL.image_uploads_in_progress[:], surviving_uploads[:])
}

@(private = "file")
try_progress_image_copies :: proc(
	p_current_uploads: [dynamic]ImageUploadInfo,
	p_surviving_uploads: ^[dynamic]ImageUploadInfo,
) -> bool {
	temp_arena := common.Arena{}
	common.temp_arena_init(&temp_arena)
	defer common.arena_delete(temp_arena)

	staging_buffer := &g_resources.buffers[get_buffer_idx(INTERNAL.staging_buffer_ref)]
	any_uploads_performed := false

	for _, i in p_current_uploads {

		image_upload_info := &p_current_uploads[i]
		common.arena_reset(temp_arena)

		if !image_upload_info.is_initialized {
			backend_image_upload_initialize(image_upload_info.image_ref)
			image_upload_info.is_initialized = true
		}

		image := &g_resources.images[get_image_idx(image_upload_info.image_ref)]
		mip_region_copies := make([dynamic]ImageMipRegionCopy, temp_arena.allocator)

		// Upload as many blocks of this texture as we can
		for {

			mip_data := image.desc.data_per_mip[image_upload_info.current_mip]

			upload_size :=
				u32(image.desc.block_size) *
				image_upload_info.single_upload_size_in_texels.x *
				image_upload_info.single_upload_size_in_texels.x

			upload_size /= 16

			if (upload_size + INTERNAL.staging_buffer_offset) >
			   INTERNAL.staging_buffer_single_region_size {
				append(p_surviving_uploads, image_upload_info^)

				if len(mip_region_copies) > 0 {
					backend_issue_image_copies(
						image_upload_info.image_ref,
						image_upload_info.current_mip,
						INTERNAL.staging_buffer_ref,
						image_upload_info.single_upload_size_in_texels,
						mip_region_copies,
					)
					any_uploads_performed = true
				}

				break
			}

			mip_dimensions := glsl.uvec2{
				image.desc.dimensions.x >> u32(image_upload_info.current_mip),
				image.desc.dimensions.y >> u32(image_upload_info.current_mip),
			}

			mip_offset_in_texels := image_upload_info.mip_offset_in_texels

			image_upload_info.mip_offset_in_texels.x +=
				image_upload_info.single_upload_size_in_texels.x
			image_upload_info.mip_offset_in_texels.x %= mip_dimensions.x

			if image_upload_info.mip_offset_in_texels.x == 0 {
				image_upload_info.mip_offset_in_texels.y +=
					image_upload_info.single_upload_size_in_texels.y
			}

			is_last_mip := image_upload_info.current_mip == 0
			mip_upload_done := image_upload_info.mip_offset_in_texels.y == mip_dimensions.y

			// Copy the data to the staging buffer
			staging_buffer_offset :=
				INTERNAL.staging_buffer_single_region_size * get_frame_idx() +
				INTERNAL.staging_buffer_offset
			INTERNAL.staging_buffer_offset += upload_size
			staging_buffer_ptr := mem.ptr_offset(staging_buffer.mapped_ptr, staging_buffer_offset)

			block_count := int(image_upload_info.single_upload_size_in_texels.y / 4)
			row_upload_size := block_count * int(image.desc.block_size)
			mip_row_size := mip_dimensions.x / 4 * u32(image.desc.block_size)
			base_row := u32(mip_offset_in_texels.y / 4)

			for row in 0 ..< block_count {

				data_offset := mip_row_size * (u32(row) + base_row)
				data_offset += u32(mip_offset_in_texels.x / 4) * u32(image.desc.block_size)

				mem.copy(staging_buffer_ptr, raw_data(mip_data[data_offset:]), row_upload_size)

				staging_buffer_ptr = mem.ptr_offset(staging_buffer_ptr, row_upload_size)
			}

			append(
				&mip_region_copies,
				ImageMipRegionCopy{
					offset = mip_offset_in_texels,
					staging_buffer_offset = staging_buffer_offset,
				},
			)

			if mip_upload_done {

				backend_issue_image_copies(
					image_upload_info.image_ref,
					image_upload_info.current_mip,
					INTERNAL.staging_buffer_ref,
					image_upload_info.single_upload_size_in_texels,
					mip_region_copies,
				)
				any_uploads_performed = true

				backend_finish_image_copy(
					image_upload_info.image_ref,
					image_upload_info.current_mip,
				)

				if is_last_mip {
					break
				}

				image_upload_info.current_mip -= 1
				image_upload_info.mip_offset_in_texels = glsl.uvec2{0, 0}
				image_upload_info.single_upload_size_in_texels = calculate_image_upload_size(
					image.desc.dimensions,
					image_upload_info.current_mip,
				)

				append(p_surviving_uploads, image_upload_info^)
				break
			}
		}
	}

	return any_uploads_performed
}

//--------------------------------------------------------------------------//

@(private = "file")
calculate_image_upload_size :: proc(p_image_dimensions: glsl.uvec3, p_mip: u8) -> glsl.uvec2 {
	size_x := min(128, p_image_dimensions.x >> u32(p_mip))
	size_y := min(128, p_image_dimensions.y >> u32(p_mip))
	return glsl.uvec2{size_x, size_y}

}

//--------------------------------------------------------------------------//

@(private)
image_upload_finalize_finished_uploads :: proc() {
	backend_finalize_async_image_copies()
}

//--------------------------------------------------------------------------//

@(private = "file")
image_allocate_new_bindless_array_entry :: proc() -> u32 {
	if len(INTERNAL.free_bindless_indices) > 0 {
		return pop(&INTERNAL.free_bindless_indices)
	}
	bindless_idx := INTERNAL.next_bindless_idx
	INTERNAL.next_bindless_idx += 1
	return bindless_idx
}

//--------------------------------------------------------------------------//
