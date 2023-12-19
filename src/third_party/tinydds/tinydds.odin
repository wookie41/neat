package tinydds

foreign import "external/tinydds.lib"

import _c "core:c"

TINY_DDS_TINYDDS_H :: 1;
MAX_MIPMAPLEVELS :: 16;
TINYIMAGEFORMAT_DXGIFORMAT :: 1;

TinyDDS_ContextHandle :: ^TinyDDS_Context;
TinyDDS_AllocFunc :: #type proc(user : rawptr, size : _c.size_t) -> rawptr;
TinyDDS_FreeFunc :: #type proc(user : rawptr, memory : rawptr);
TinyDDS_ReadFunc :: #type proc(user : rawptr, buffer : rawptr, byteCount : _c.size_t, header : bool) -> _c.size_t;
TinyDDS_SeekFunc :: #type proc(user : rawptr, offset : i64) -> bool;
TinyDDS_TellFunc :: #type proc(user : rawptr) -> i64;
TinyDDS_ErrorFunc :: #type proc(user : rawptr, msg : cstring);
TinyDDS_WriteFunc :: #type proc(user : rawptr, buffer : rawptr, byteCount : _c.size_t);

TinyImageFormat_DXGI_FORMAT :: enum i32 {
    TifDxgiFormatUnknown = 0,
    TifDxgiFormatR32G32B32A32Typeless = 1,
    TifDxgiFormatR32G32B32A32Float = 2,
    TifDxgiFormatR32G32B32A32Uint = 3,
    TifDxgiFormatR32G32B32A32Sint = 4,
    TifDxgiFormatR32G32B32Typeless = 5,
    TifDxgiFormatR32G32B32Float = 6,
    TifDxgiFormatR32G32B32Uint = 7,
    TifDxgiFormatR32G32B32Sint = 8,
    TifDxgiFormatR16G16B16A16Typeless = 9,
    TifDxgiFormatR16G16B16A16Float = 10,
    TifDxgiFormatR16G16B16A16Unorm = 11,
    TifDxgiFormatR16G16B16A16Uint = 12,
    TifDxgiFormatR16G16B16A16Snorm = 13,
    TifDxgiFormatR16G16B16A16Sint = 14,
    TifDxgiFormatR32G32Typeless = 15,
    TifDxgiFormatR32G32Float = 16,
    TifDxgiFormatR32G32Uint = 17,
    TifDxgiFormatR32G32Sint = 18,
    TifDxgiFormatR32G8X24Typeless = 19,
    TifDxgiFormatD32FloatS8X24Uint = 20,
    TifDxgiFormatR32FloatX8X24Typeless = 21,
    TifDxgiFormatX32TypelessG8X24Uint = 22,
    TifDxgiFormatR10G10B10A2Typeless = 23,
    TifDxgiFormatR10G10B10A2Unorm = 24,
    TifDxgiFormatR10G10B10A2Uint = 25,
    TifDxgiFormatR11G11B10Float = 26,
    TifDxgiFormatR8G8B8A8Typeless = 27,
    TifDxgiFormatR8G8B8A8Unorm = 28,
    TifDxgiFormatR8G8B8A8UnormSrgb = 29,
    TifDxgiFormatR8G8B8A8Uint = 30,
    TifDxgiFormatR8G8B8A8Snorm = 31,
    TifDxgiFormatR8G8B8A8Sint = 32,
    TifDxgiFormatR16G16Typeless = 33,
    TifDxgiFormatR16G16Float = 34,
    TifDxgiFormatR16G16Unorm = 35,
    TifDxgiFormatR16G16Uint = 36,
    TifDxgiFormatR16G16Snorm = 37,
    TifDxgiFormatR16G16Sint = 38,
    TifDxgiFormatR32Typeless = 39,
    TifDxgiFormatD32Float = 40,
    TifDxgiFormatR32Float = 41,
    TifDxgiFormatR32Uint = 42,
    TifDxgiFormatR32Sint = 43,
    TifDxgiFormatR24G8Typeless = 44,
    TifDxgiFormatD24UnormS8Uint = 45,
    TifDxgiFormatR24UnormX8Typeless = 46,
    TifDxgiFormatX24TypelessG8Uint = 47,
    TifDxgiFormatR8G8Typeless = 48,
    TifDxgiFormatR8G8Unorm = 49,
    TifDxgiFormatR8G8Uint = 50,
    TifDxgiFormatR8G8Snorm = 51,
    TifDxgiFormatR8G8Sint = 52,
    TifDxgiFormatR16Typeless = 53,
    TifDxgiFormatR16Float = 54,
    TifDxgiFormatD16Unorm = 55,
    TifDxgiFormatR16Unorm = 56,
    TifDxgiFormatR16Uint = 57,
    TifDxgiFormatR16Snorm = 58,
    TifDxgiFormatR16Sint = 59,
    TifDxgiFormatR8Typeless = 60,
    TifDxgiFormatR8Unorm = 61,
    TifDxgiFormatR8Uint = 62,
    TifDxgiFormatR8Snorm = 63,
    TifDxgiFormatR8Sint = 64,
    TifDxgiFormatA8Unorm = 65,
    TifDxgiFormatR1Unorm = 66,
    TifDxgiFormatR9G9B9E5Sharedexp = 67,
    TifDxgiFormatR8G8B8G8Unorm = 68,
    TifDxgiFormatG8R8G8B8Unorm = 69,
    TifDxgiFormatBc1Typeless = 70,
    TifDxgiFormatBc1Unorm = 71,
    TifDxgiFormatBc1UnormSrgb = 72,
    TifDxgiFormatBc2Typeless = 73,
    TifDxgiFormatBc2Unorm = 74,
    TifDxgiFormatBc2UnormSrgb = 75,
    TifDxgiFormatBc3Typeless = 76,
    TifDxgiFormatBc3Unorm = 77,
    TifDxgiFormatBc3UnormSrgb = 78,
    TifDxgiFormatBc4Typeless = 79,
    TifDxgiFormatBc4Unorm = 80,
    TifDxgiFormatBc4Snorm = 81,
    TifDxgiFormatBc5Typeless = 82,
    TifDxgiFormatBc5Unorm = 83,
    TifDxgiFormatBc5Snorm = 84,
    TifDxgiFormatB5G6R5Unorm = 85,
    TifDxgiFormatB5G5R5A1Unorm = 86,
    TifDxgiFormatB8G8R8A8Unorm = 87,
    TifDxgiFormatB8G8R8X8Unorm = 88,
    TifDxgiFormatR10G10B10XrBiasA2Unorm = 89,
    TifDxgiFormatB8G8R8A8Typeless = 90,
    TifDxgiFormatB8G8R8A8UnormSrgb = 91,
    TifDxgiFormatB8G8R8X8Typeless = 92,
    TifDxgiFormatB8G8R8X8UnormSrgb = 93,
    TifDxgiFormatBc6HTypeless = 94,
    TifDxgiFormatBc6HUf16 = 95,
    TifDxgiFormatBc6HSf16 = 96,
    TifDxgiFormatBc7Typeless = 97,
    TifDxgiFormatBc7Unorm = 98,
    TifDxgiFormatBc7UnormSrgb = 99,
    TifDxgiFormatAyuv = 100,
    TifDxgiFormatY410 = 101,
    TifDxgiFormatY416 = 102,
    TifDxgiFormatNv12 = 103,
    TifDxgiFormatP010 = 104,
    TifDxgiFormatP016 = 105,
    TifDxgiFormat420Opaque = 106,
    TifDxgiFormatYuy2 = 107,
    TifDxgiFormatY210 = 108,
    TifDxgiFormatY216 = 109,
    TifDxgiFormatNv11 = 110,
    TifDxgiFormatAi44 = 111,
    TifDxgiFormatIa44 = 112,
    TifDxgiFormatP8 = 113,
    TifDxgiFormatA8P8 = 114,
    TifDxgiFormatB4G4R4A4Unorm = 115,
    TifDxgiFormatR10G10B107E3A2Float = 116,
    TifDxgiFormatR10G10B106E4A2Float = 117,
    TifDxgiFormatD16UnormS8Uint = 118,
    TifDxgiFormatR16UnormX8Typeless = 119,
    TifDxgiFormatX16TypelessG8Uint = 120,
    TifDxgiFormatP208 = 130,
    TifDxgiFormatV208 = 131,
    TifDxgiFormatV408 = 132,
    TifDxgiFormatR10G10B10SnormA2Unorm = 189,
    TifDxgiFormatR4G4Unorm = 190,
};

TinyDDS_Format :: enum i32 {
    TddsUndefined = 0,
    TddsB5G6R5Unorm = 85,
    TddsB5G5R5A1Unorm = 86,
    TddsR8Unorm = 61,
    TddsR8Snorm = 63,
    TddsA8Unorm = 65,
    TddsR1Unorm = 66,
    TddsR8Uint = 62,
    TddsR8Sint = 64,
    TddsR8G8Unorm = 49,
    TddsR8G8Snorm = 51,
    TddsR8G8Uint = 50,
    TddsR8G8Sint = 52,
    TddsR8G8B8A8Unorm = 28,
    TddsR8G8B8A8Snorm = 31,
    TddsR8G8B8A8Uint = 30,
    TddsR8G8B8A8Sint = 32,
    TddsR8G8B8A8Srgb = 29,
    TddsB8G8R8A8Unorm = 87,
    TddsB8G8R8A8Srgb = 91,
    TddsR9G9B9E5Ufloat = 67,
    TddsR10G10B10A2Unorm = 24,
    TddsR10G10B10A2Uint = 25,
    TddsR11G11B10Ufloat = 26,
    TddsR16Unorm = 56,
    TddsR16Snorm = 58,
    TddsR16Uint = 57,
    TddsR16Sint = 59,
    TddsR16Sfloat = 54,
    TddsR16G16Unorm = 35,
    TddsR16G16Snorm = 37,
    TddsR16G16Uint = 36,
    TddsR16G16Sint = 38,
    TddsR16G16Sfloat = 34,
    TddsR16G16B16A16Unorm = 11,
    TddsR16G16B16A16Snorm = 13,
    TddsR16G16B16A16Uint = 12,
    TddsR16G16B16A16Sint = 14,
    TddsR16G16B16A16Sfloat = 10,
    TddsR32Uint = 42,
    TddsR32Sint = 43,
    TddsR32Sfloat = 41,
    TddsR32G32Uint = 17,
    TddsR32G32Sint = 18,
    TddsR32G32Sfloat = 16,
    TddsR32G32B32Uint = 7,
    TddsR32G32B32Sint = 8,
    TddsR32G32B32Sfloat = 6,
    TddsR32G32B32A32Uint = 3,
    TddsR32G32B32A32Sint = 4,
    TddsR32G32B32A32Sfloat = 2,
    TddsBc1RgbaUnormBlock = 71,
    TddsBc1RgbaSrgbBlock = 72,
    TddsBc2UnormBlock = 74,
    TddsBc2SrgbBlock = 75,
    TddsBc3UnormBlock = 77,
    TddsBc3SrgbBlock = 78,
    TddsBc4UnormBlock = 80,
    TddsBc4SnormBlock = 81,
    TddsBc5UnormBlock = 83,
    TddsBc5SnormBlock = 84,
    TddsBc6HUfloatBlock = 95,
    TddsBc6HSfloatBlock = 96,
    TddsBc7UnormBlock = 98,
    TddsBc7SrgbBlock = 99,
    TddsAyuv = 100,
    TddsY410 = 101,
    TddsY416 = 102,
    TddsNv12 = 103,
    TddsP010 = 104,
    TddsP016 = 105,
    Tdds420Opaque = 106,
    TddsYuy2 = 107,
    TddsY210 = 108,
    TddsY216 = 109,
    TddsNv11 = 110,
    TddsAi44 = 111,
    TddsIa44 = 112,
    TddsP8 = 113,
    TddsA8P8 = 114,
    TddsB4G4R4A4Unorm = 115,
    TddsR10G10B107E3A2Float = 116,
    TddsR10G10B106E4A2Float = 117,
    TddsD16UnormS8Uint = 118,
    TddsR16UnormX8Typeless = 119,
    TddsX16TypelessG8Uint = 120,
    TddsP208 = 130,
    TddsV208 = 131,
    TddsV408 = 132,
    TddsR10G10B10SnormA2Unorm = 189,
    TddsR4G4Unorm = 190,
    TddsSynthesisedDxgiformats = 65535,
    TddsG4R4Unorm = 65535,
    TddsA4B4G4R4Unorm,
    TddsX4B4G4R4Unorm,
    TddsA4R4G4B4Unorm,
    TddsX4R4G4B4Unorm,
    TddsB4G4R4X4Unorm,
    TddsR4G4B4A4Unorm,
    TddsR4G4B4X4Unorm,
    TddsB5G5R5X1Unorm,
    TddsR5G5B5A1Unorm,
    TddsR5G5B5X1Unorm,
    TddsA1R5G5B5Unorm,
    TddsX1R5G5B5Unorm,
    TddsA1B5G5R5Unorm,
    TddsX1B5G5R5Unorm,
    TddsR5G6B5Unorm,
    TddsB2G3R3Unorm,
    TddsB2G3R3A8Unorm,
    TddsG8R8Unorm,
    TddsG8R8Snorm,
    TddsR8G8B8Unorm,
    TddsB8G8R8Unorm,
    TddsA8B8G8R8Snorm,
    TddsB8G8R8A8Snorm,
    TddsR8G8B8X8Unorm,
    TddsB8G8R8X8Unorm,
    TddsA8B8G8R8Unorm,
    TddsX8B8G8R8Unorm,
    TddsA8R8G8B8Unorm,
    TddsX8R8G8B8Unorm,
    TddsR10G10B10A2Snorm,
    TddsB10G10R10A2Unorm,
    TddsB10G10R10A2Snorm,
    TddsA2B10G10R10Unorm,
    TddsA2B10G10R10Snorm,
    TddsA2R10G10B10Unorm,
    TddsA2R10G10B10Snorm,
    TddsG16R16Unorm,
    TddsG16R16Snorm,
};

TinyDDS_Context :: struct {};

TinyDDS_Callbacks :: struct {
    errorFn : TinyDDS_ErrorFunc,
    allocFn : TinyDDS_AllocFunc,
    allocTempFn : TinyDDS_AllocFunc,
    freeFn : TinyDDS_FreeFunc,
    freeTempFn : TinyDDS_FreeFunc,
    readFn : TinyDDS_ReadFunc,
    seekFn : TinyDDS_SeekFunc,
    tellFn : TinyDDS_TellFunc,
};

TinyDDS_WriteCallbacks :: struct {
    error : TinyDDS_ErrorFunc,
    alloc : TinyDDS_AllocFunc,
    free : TinyDDS_FreeFunc,
    write : TinyDDS_WriteFunc,
};

@(default_calling_convention="c")
foreign tinydds {

    @(link_name="TinyDDS_CreateContext")
    create_context :: proc(callbacks : ^TinyDDS_Callbacks, user : rawptr) -> TinyDDS_ContextHandle ---;

    @(link_name="TinyDDS_DestroyContext")
    destroy_context :: proc(handle : TinyDDS_ContextHandle) ---;

    @(link_name="TinyDDS_Reset")
    reset :: proc(handle : TinyDDS_ContextHandle) ---;

    @(link_name="TinyDDS_ReadHeader")
    read_header :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_Is1D")
    is1_d :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_Is2D")
    is2_d :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_Is3D")
    is3_d :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_IsCubemap")
    is_cubemap :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_IsArray")
    is_array :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_Dimensions")
    dimensions :: proc(handle : TinyDDS_ContextHandle, width : ^u32, height : ^u32, depth : ^u32, slices : ^u32) -> bool ---;

    @(link_name="TinyDDS_Width")
    width :: proc(handle : TinyDDS_ContextHandle) -> u32 ---;

    @(link_name="TinyDDS_Height")
    height :: proc(handle : TinyDDS_ContextHandle) -> u32 ---;

    @(link_name="TinyDDS_Depth")
    depth :: proc(handle : TinyDDS_ContextHandle) -> u32 ---;

    @(link_name="TinyDDS_ArraySlices")
    array_slices :: proc(handle : TinyDDS_ContextHandle) -> u32 ---;

    @(link_name="TinyDDS_NeedsGenerationOfMipmaps")
    needs_generation_of_mipmaps :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_NeedsEndianCorrecting")
    needs_endian_correcting :: proc(handle : TinyDDS_ContextHandle) -> bool ---;

    @(link_name="TinyDDS_NumberOfMipmaps")
    number_of_mipmaps :: proc(handle : TinyDDS_ContextHandle) -> u32 ---;

    @(link_name="TinyDDS_ImageSize")
    image_size :: proc(handle : TinyDDS_ContextHandle, mipmaplevel : u32) -> u32 ---;

    @(link_name="TinyDDS_FaceSize")
    face_size :: proc(handle : TinyDDS_ContextHandle, mipmaplevel : u32) -> u32 ---;

    @(link_name="TinyDDS_ImageRawData")
    image_raw_data :: proc(handle : TinyDDS_ContextHandle, depth : u32, mipmaplevel : u32) -> rawptr ---;

    @(link_name="TinyDDS_GetFormat")
    get_format :: proc(handle : TinyDDS_ContextHandle) -> TinyDDS_Format ---;

    @(link_name="TinyDDS_WriteImage")
    write_image :: proc(callbacks : ^TinyDDS_WriteCallbacks, user : rawptr, width : u32, height : u32, depth : u32, slices : u32, mipmaplevels : u32, format : TinyDDS_Format, cubemap : bool, preferDx10Format : bool, mipmapsizes : ^u32, mipmaps : ^rawptr) -> bool ---;

}
