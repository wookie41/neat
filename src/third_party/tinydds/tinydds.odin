package tinydds

foreign import "tinydds.lib"

import _c "core:c"



DDSD_FLAGS :: enum i32 {
    DdsdCaps = 1,
    DdsdHeight = 2,
    DdsdWidth = 4,
    DdsdPitch = 8,
    DdsdPixelformat = 4096,
    DdsdMipmapcount = 131072,
    DdsdLinearsize = 524288,
    DdsdDepth = 8388608,
};

DDSC_FLAGS :: enum i32 {
    DdscapsComplex = 8,
    DdscapsTexture = 4096,
    DdscapsMipmap = 4194304,
};

DDSC_FLAGS2 :: enum i32 {
    Ddscaps2Cubemap = 512,
    Ddscaps2CubemapPositivex = 1024,
    Ddscaps2CubemapNegativex = 2048,
    Ddscaps2CubemapPositivey = 4096,
    Ddscaps2CubemapNegativey = 8192,
    Ddscaps2CubemapPositivez = 16384,
    Ddscaps2CubemapNegativez = 32768,
    Ddscaps2Volume = 2097152,
};

DDPF_FLAGS :: enum i32 {
    DdpfAlphapixels = 1,
    DdpfAlpha = 2,
    DdpfFourcc = 4,
    DdpfRgb = 64,
    DdpfYuv = 512,
    DdpfLuminance = 131072,
};

DXGI_FORMAT :: enum i32 {
    Unknown = 0,
    R32G32B32A32Typeless = 1,
    R32G32B32A32Float = 2,
    R32G32B32A32Uint = 3,
    R32G32B32A32Sint = 4,
    R32G32B32Typeless = 5,
    R32G32B32Float = 6,
    R32G32B32Uint = 7,
    R32G32B32Sint = 8,
    R16G16B16A16Typeless = 9,
    R16G16B16A16Float = 10,
    R16G16B16A16Unorm = 11,
    R16G16B16A16Uint = 12,
    R16G16B16A16Snorm = 13,
    R16G16B16A16Sint = 14,
    R32G32Typeless = 15,
    R32G32Float = 16,
    R32G32Uint = 17,
    R32G32Sint = 18,
    R32G8X24Typeless = 19,
    D32FloatS8X24Uint = 20,
    R32FloatX8X24Typeless = 21,
    X32TypelessG8X24Uint = 22,
    R10G10B10A2Typeless = 23,
    R10G10B10A2Unorm = 24,
    R10G10B10A2Uint = 25,
    R11G11B10Float = 26,
    R8G8B8A8Typeless = 27,
    R8G8B8A8Unorm = 28,
    R8G8B8A8UnormSrgb = 29,
    R8G8B8A8Uint = 30,
    R8G8B8A8Snorm = 31,
    R8G8B8A8Sint = 32,
    R16G16Typeless = 33,
    R16G16Float = 34,
    R16G16Unorm = 35,
    R16G16Uint = 36,
    R16G16Snorm = 37,
    R16G16Sint = 38,
    R32Typeless = 39,
    D32Float = 40,
    R32Float = 41,
    R32Uint = 42,
    R32Sint = 43,
    R24G8Typeless = 44,
    D24UnormS8Uint = 45,
    R24UnormX8Typeless = 46,
    X24TypelessG8Uint = 47,
    R8G8Typeless = 48,
    R8G8Unorm = 49,
    R8G8Uint = 50,
    R8G8Snorm = 51,
    R8G8Sint = 52,
    R16Typeless = 53,
    R16Float = 54,
    D16Unorm = 55,
    R16Unorm = 56,
    R16Uint = 57,
    R16Snorm = 58,
    R16Sint = 59,
    R8Typeless = 60,
    R8Unorm = 61,
    R8Uint = 62,
    R8Snorm = 63,
    R8Sint = 64,
    A8Unorm = 65,
    R1Unorm = 66,
    R9G9B9E5Sharedexp = 67,
    R8G8B8G8Unorm = 68,
    G8R8G8B8Unorm = 69,
    Bc1Typeless = 70,
    Bc1Unorm = 71,
    Bc1UnormSrgb = 72,
    Bc2Typeless = 73,
    Bc2Unorm = 74,
    Bc2UnormSrgb = 75,
    Bc3Typeless = 76,
    Bc3Unorm = 77,
    Bc3UnormSrgb = 78,
    Bc4Typeless = 79,
    Bc4Unorm = 80,
    Bc4Snorm = 81,
    Bc5Typeless = 82,
    Bc5Unorm = 83,
    Bc5Snorm = 84,
    B5G6R5Unorm = 85,
    B5G5R5A1Unorm = 86,
    B8G8R8A8Unorm = 87,
    B8G8R8X8Unorm = 88,
    R10G10B10XrBiasA2Unorm = 89,
    B8G8R8A8Typeless = 90,
    B8G8R8A8UnormSrgb = 91,
    B8G8R8X8Typeless = 92,
    B8G8R8X8UnormSrgb = 93,
    Bc6HTypeless = 94,
    Bc6HUf16 = 95,
    Bc6HSf16 = 96,
    Bc7Typeless = 97,
    Bc7Unorm = 98,
    Bc7UnormSrgb = 99,
    Ayuv = 100,
    Y410 = 101,
    Y416 = 102,
    Nv12 = 103,
    P010 = 104,
    P016 = 105,
    Opaque = 106,
    Yuy2 = 107,
    Y210 = 108,
    Y216 = 109,
    Nv11 = 110,
    Ai44 = 111,
    Ia44 = 112,
    P8 = 113,
    A8P8 = 114,
    B4G4R4A4Unorm = 115,
    P208 = 130,
    V208 = 131,
    V408 = 132,
    ForceUint = 4294967295,
};

D3D10_RESOURCE_DIMENSION :: enum i32 {
    D3D10ResourceDimensionUnknown = 0,
    D3D10ResourceDimensionBuffer = 1,
    D3D10ResourceDimensionTexture1D = 2,
    D3D10ResourceDimensionTexture2D = 3,
    D3D10ResourceDimensionTexture3D = 4,
};

D3D10_RESOURCE_MISC_FLAG :: enum i32 {
    D3D10ResourceMiscGenerateMips = 1,
    D3D10ResourceMiscShared = 2,
    D3D10ResourceMiscTexturecube = 4,
    D3D10ResourceMiscSharedKeyedmutex = 16,
    D3D10ResourceMiscGdiCompatible = 32,
};

D3D11_RESOURCE_MISC_FLAG :: enum i32 {
    D3D11ResourceMiscGenerateMips = 1,
    D3D11ResourceMiscShared = 2,
    D3D11ResourceMiscTexturecube = 4,
    D3D11ResourceMiscDrawindirectArgs = 16,
    D3D11ResourceMiscBufferAllowRawViews = 32,
    D3D11ResourceMiscBufferStructured = 64,
    D3D11ResourceMiscResourceClamp = 128,
    D3D11ResourceMiscSharedKeyedmutex = 256,
    D3D11ResourceMiscGdiCompatible = 512,
    D3D11ResourceMiscSharedNthandle = 2048,
    D3D11ResourceMiscRestrictedContent = 4096,
    D3D11ResourceMiscRestrictSharedResource = 8192,
    D3D11ResourceMiscRestrictSharedResourceDriver = 16384,
    D3D11ResourceMiscGuarded = 32768,
    D3D11ResourceMiscTilePool = 131072,
    D3D11ResourceMiscTiled = 262144,
    D3D11ResourceMiscHwProtected = 524288,
};

DX10_MISC_FLAG :: enum i32 {
    DdsAlphaModeUnknown = 0,
    DdsAlphaModeStraight = 1,
    DdsAlphaModePremultiplied = 2,
    DdsAlphaModeOpaque = 3,
    DdsAlphaModeCustom = 4,
};

DDS_PIXELFORMAT :: struct {
    dwSize : u32,
    dwFlags : u32,
    dwFourCC : u32,
    dwRGBBitCount : u32,
    dwRBitMask : u32,
    dwGBitMask : u32,
    dwBBitMask : u32,
    dwABitMask : u32,
};

DDS_HEADER_DXT10 :: struct {
    dxgiFormat : DXGI_FORMAT,
    resourceDimension : D3D10_RESOURCE_DIMENSION,
    miscFlag : u32,
    arraySize : u32,
    miscFlags2 : u32,
};

DDSFile :: struct {
    dwSize : u32,
    dwFlags : u32,
    dwHeight : u32,
    dwWidth : u32,
    dwPitchOrLinearSize : u32,
    dwDepth : u32,
    dwMipMapCount : u32,
    dwReserved1 : [11]u32,
    ddspf : DDS_PIXELFORMAT,
    dwCaps : u32,
    dwCaps2 : u32,
    dwCaps3 : u32,
    dwCaps4 : u32,
    dwReserved2 : u32,
    ddsHeaderDx10 : ^DDS_HEADER_DXT10,
    dwFileSize : u32,
    dwBufferSize : u32,
    blBuffer : ^_c.uchar,
};

@(default_calling_convention="c")
foreign tinydds {

    @(link_name="dds_load")
    dds_load :: proc(path : cstring) -> ^DDSFile ---;

    @(link_name="dds_free")
    dds_free :: proc(file : ^DDSFile) ---;

}
