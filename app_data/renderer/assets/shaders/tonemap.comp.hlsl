#include "fullscreen_compute.hlsli"
#include "resources.hlsli"
#include "common.hlsli"

//---------------------------------------------------------------------------//

[[vk::binding(1, 0)]]
Texture2D<float4> sceneHDR : register(t0, space0);

[[vk::binding(2, 0)]]
RWTexture2D<float4> sceneSDR : register(u0, space0);

//---------------------------------------------------------------------------//

// simple fit from: https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
float3 ACESFilmApproximate(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0, 1);
}

//---------------------------------------------------------------------------//

float3 RRTAndODTFit(float3 v)
{
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

//---------------------------------------------------------------------------//

float3 ACESFitted(float3 color)
{
    // code from: https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
    // licensed under MIT license
    float3x3 ACESInputMat =
        {
            { 0.59719, 0.35458, 0.04823 },
            { 0.07600, 0.90834, 0.01566 },
            { 0.02840, 0.13383, 0.83777 }
        };
    // ACESInputMat = transpose(ACESInputMat);

    // ODT_SAT => XYZ => D60_2_D65 => sRGB
    float3x3 ACESOutputMat =
        {
            { 1.60475, -0.53108, -0.07367 },
            { -0.10208, 1.10813, -0.00605 },
            { -0.00327, -0.07276, 1.07602 }
        };
    // ACESInputMat = transpose(ACESInputMat);
    color = mul(ACESInputMat, color);

    // Apply RRT and ODT
    color = RRTAndODTFit(color);
    color = mul(ACESOutputMat, color);
    color = clamp(color, 0, 1);
    return color;
}

//---------------------------------------------------------------------------//

float3 EncodeSRGB(float3 c) {
    float3 result;
    if (c.r <= 0.0031308) {
        result.r = c.r * 12.92;
    } else {
        result.r = 1.055 * pow(c.r, 1.0 / 2.4) - 0.055;
    }

    if (c.g <= 0.0031308) {
        result.g = c.g * 12.92;
    } else {
        result.g = 1.055 * pow(c.g, 1.0 / 2.4) - 0.055;
    }

    if (c.b <= 0.0031308) {
        result.b = c.b * 12.92;
    } else {
        result.b = 1.055 * pow(c.b, 1.0 / 2.4) - 0.055;
    }

    return clamp(result, 0.0, 1.0);
}
[numthreads(8, 8, 1)]
void CSMain(uint2 dispatchThreadId: SV_DispatchThreadID)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);

    const float3 linearColor = sceneHDR[input.cellCoord].rgb;
    const float3 tonemapped = ACESFitted(linearColor);
    const float3 sRGB = LinearTosRGB(tonemapped);

    sceneSDR[input.cellCoord] = float4(DitherRGB8(sRGB, input.cellCoord, uPerFrame.Time), 1);
}

//---------------------------------------------------------------------------//