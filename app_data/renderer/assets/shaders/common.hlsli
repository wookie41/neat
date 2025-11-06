#ifndef COMMON_H
#define COMMON_H

//---------------------------------------------------------------------------//

#define RGB_TO_LUM float3(0.2125, 0.7154, 0.0721)

//---------------------------------------------------------------------------//

#define EPS_3 1e-3
#define EPS_6 1e-6
#define EPS_9 1e-9

//---------------------------------------------------------------------------//

struct ExposureInfo
{
    float AvgLum;
    float EV100;
    float Exposure;
};

// Convert RGB value to Luminance
inline float RGBToLuminance(in float3 hdrColor)
{
    return dot(hdrColor, RGB_TO_LUM);
};

//---------------------------------------------------------------------------//

// Reference https://seblagarde.wordpress.com/wp-content/uploads/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf
float ComputeEV100FromAvgLuminance(float avgLuminance)
{
    return log2(avgLuminance * 100.0f / 12.5f);
}

//---------------------------------------------------------------------------//

// Reference https://seblagarde.wordpress.com/wp-content/uploads/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf
float ConvertEV100ToExposure(float EV100)
{
    float maxLuminance = 1.2f * pow(2.0f, EV100);
    return 1.0f / maxLuminance;
}

//---------------------------------------------------------------------------//

float3 LinearTosRGB(float3 linearColor)
{
    float3 sRGBLo = linearColor * 12.92;
    float3 sRGBHi = (pow(abs(linearColor), (1.0 / 2.4)) * 1.055) - 0.055;
    float3 sRGB;
    sRGB.x = linearColor.x <= 0.0031308 ? sRGBLo.x : sRGBHi.x;
    sRGB.y = linearColor.y <= 0.0031308 ? sRGBLo.y : sRGBHi.y;
    sRGB.z = linearColor.z <= 0.0031308 ? sRGBLo.z : sRGBHi.z;
    return sRGB;
}

//---------------------------------------------------------------------------//

float3 sRGBToLinear(float3 linearColor)
{
    float3 sRGBLo = linearColor / 12.92;
    float3 sRGBHi = (pow(abs(linearColor + 0.055) / 1.055, 2.4));
    float3 sRGB;
    sRGB.x = linearColor.x <= 0.004045 ? sRGBLo.x : sRGBHi.x;
    sRGB.y = linearColor.y <= 0.004045 ? sRGBLo.y : sRGBHi.y;
    sRGB.z = linearColor.z <= 0.004045 ? sRGBLo.z : sRGBHi.z;
    return sRGB;
}

//---------------------------------------------------------------------------//

float ToLinear1(float c)
{
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

//---------------------------------------------------------------------------//

float ToSrgb1(float c)
{
    return (c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055);
}
//---------------------------------------------------------------------------//

float3 LinearToYCoCg(float3 linearColor)
{
    return float3(
        linearColor.x * 0.25 + 0.5 * linearColor.y + 0.25 * linearColor.z,
        linearColor.x * 0.5 - 0.5 * linearColor.z,
        -linearColor.x * 0.25 + 0.5 * linearColor.y - 0.25 * linearColor.z);
}

//---------------------------------------------------------------------------//

float3 YCoCgToLinear(float3 YCoCg)
{
    return float3(
        YCoCg.x + YCoCg.y - YCoCg.z,
        YCoCg.x + YCoCg.z,
        YCoCg.x - YCoCg.y - YCoCg.z);
}

//---------------------------------------------------------------------------//

#define UI0 1597334673U
#define UI1 3812015801U
#define UI2 uint3(UI0, UI1)
#define UI3 uint3(UI0, UI1, 2798796415U)
#define UIF (1.0 / float(0xffffffffU))

float3 Hash32(float2 q)
{
    uint3 n = uint3(int3(q.xyx)) * UI3;
    n = (n.x ^ n.y ^ n.z) * UI3;
    return float3(n) * UIF;
}

//---------------------------------------------------------------------------//

float3 DitherRGB8(float3 c, int2 uv, float time)
{
    float3 noise = Hash32(uint2(uv * time));
    noise += Hash32(uint2((uv + float2(165, 1292)) * time));
    noise -= 1.f;
    noise /= 255.f; // least significant of 8 bits
    return c + noise;
}

//---------------------------------------------------------------------------//

float4 UnpackColorRGBA(uint color)
{
    return float4((color & 0xffu) / 255.f,
                  ((color >> 8u) & 0xffu) / 255.f,
                  ((color >> 16u) & 0xffu) / 255.f,
                  ((color >> 24u) & 0xffu) / 255.f);
}
//---------------------------------------------------------------------------//

#endif // COMMON_H