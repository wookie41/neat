#ifndef COMMON_H
#define COMMON_H

#include "math.hlsli"
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

float2 ComputeMotionVector(in float4 positionClip, in float4 prevPositionClip, in float2 jitter, in float2 previousJitter)
{
    const float2 posNDC = (positionClip.xy / positionClip.w) - jitter;
    const float2 prevNDC = (prevPositionClip.xy / prevPositionClip.w) - previousJitter;

    return (prevNDC - posNDC) * 0.5;
}

//---------------------------------------------------------------------------//

bool IsUVOutOfRange(in float2 uv)
{
    return uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1;
}

//---------------------------------------------------------------------------//

float2 UnjitterUV(in float2 uv, in float2 jitter)
{
    return uv - ddx_fine(uv) * jitter.x + ddy_fine(uv.y) * jitter.y;
}

//---------------------------------------------------------------------------//

// reference: "Filmic SMAA" Siggraph presentation, page 90
float3 BicubicSample5Tap(in Texture2D<float3> srcTexture, in SamplerState srcSampler, in float2 uv, in float2 texelSize) 
{
    const float2 uvTrunc = floor(uv - 0.5) + 0.5f;
    const float2 f = uv - uvTrunc;
    const float2 f2 = f * f;
    const float2 f3 = f2 * f;

    const float2 w0 = -0.5 * f3 + f2 - 0.5 * f;
    const float2 w1 = 1.5 * f3 - 2.5 * f2 + 1.f;
    const float2 w2 = -1.5 * f3 + 2.f * f2 + 0.5 * f;
    const float2 w3 = 0.5 * f3 - 0.5 * f2;

    const float2 wB = w1 + w2;
    const float2 t = w2 / wB;

    float2 uv0 = uvTrunc - 1;
    float2 uvT = uvTrunc + t;
    float2 uv3 = uvTrunc + 2;

    uv0 *= texelSize;
    uvT *= texelSize;
    uv3 *= texelSize;

    const float4 result =
        float4(srcTexture.SampleLevel(srcSampler, float2(uv0.x, uvT.y), 0), 1.f) * w0.x * wB.y +
        float4(srcTexture.SampleLevel(srcSampler, float2(uvT.x, uv0.y), 0), 1.f) * wB.x * w0.y +
        float4(srcTexture.SampleLevel(srcSampler, float2(uvT.x, uvT.y), 0), 1.f) * wB.x * wB.y +
        float4(srcTexture.SampleLevel(srcSampler, float2(uvT.x, uv3.y), 0), 1.f) * wB.x * w3.y +
        float4(srcTexture.SampleLevel(srcSampler, float2(uv3.x, uvT.y), 0), 1.f) * w3.x * wB.y;

    // normalize by dividing trough total weight
    // total weight is stored in alpha
    return result.rgb / result.a;
}

//---------------------------------------------------------------------------//

float FilterBlackmanHarris(in float value) 
{
    const float x = 1.0f - value;

    const float a0 = 0.35875f;
    const float a1 = 0.48829f;
    const float a2 = 0.14128f;
    const float a3 = 0.01168f;

    return saturate(a0 - a1 * cos(MATH_PI * x) + a2 * cos(2 * MATH_PI * x) - a3 * cos(3 * MATH_PI * x));
}

//---------------------------------------------------------------------------//

// Optimized clip aabb function from 
// https://github.com/playdeadgames/publications/blob/master/INSIDE/rendering_inside_gdc2016.pdf
float4 ClipAABB(in float3 aabbMin, float3 aabbMax, in float4 previousSample, in float averageAlpha) 
{

    // note: only clips towards aabb center (but fast!)
    const float3 pClip = 0.5 * (aabbMax + aabbMin);
    const float3 eClip = 0.5 * (aabbMax - aabbMin) + 0.000000001f;

    const float4 vClip = previousSample - float4(pClip, averageAlpha);
    const float3 vUnit = vClip.xyz / eClip;
    const float3 aUnit = abs(vUnit);
    const float maUnit = max(aUnit.x, max(aUnit.y, aUnit.z));

    if (maUnit > 1.0) 
        return float4(pClip, averageAlpha) + vClip / maUnit;
    
    // point inside aabb
    return previousSample;
}

//---------------------------------------------------------------------------//

//reverseable 'tonemapping' function and it's counterpart
//see "High Quality Temporal Supersampling", page 20

float3 Tonemap(in float3 color)
{
    return color / (1 + RGBToLuminance(color));
}

float3 TonemapReverse(in float3 color)
{
    return color / (1 - RGBToLuminance(color));
}

//---------------------------------------------------------------------------//

#endif // COMMON_H