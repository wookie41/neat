//---------------------------------------------------------------------------//

#define NUM_THREADS_X 16
#define NUM_THREADS_Y 16
#define THREAD_GROUP_SIZE (NUM_THREADS_X * NUM_THREADS_Y)
#define NUM_NON_ZERO_BINS float(THREAD_GROUP_SIZE - 2)

//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "fullscreen_compute.hlsli"
#include "resources.hlsli"

//---------------------------------------------------------------------------//

// Inputs

[[vk::binding(1, 0)]]
cbuffer BuildLuminanceHistogramParams : register(b1, space0)
{
    float minLuminanceLog;
    float invLuminanceRange;
    uint2 _padding;
}

[[vk::binding(2, 0)]]
Texture2D<float4> lastSceneHDRTex : register(t0, space0);

[[vk::binding(3, 0)]]
StructuredBuffer<ExposureInfo> exposureInfoBuffer : register(t1, space0);


//---------------------------------------------------------------------------//

// Outputs

[[vk::binding(4, 0)]]
RWStructuredBuffer<uint> luminanceHistogram : register(u0, space0);

//---------------------------------------------------------------------------//

groupshared uint luminanceHistogramShared[THREAD_GROUP_SIZE];

//---------------------------------------------------------------------------//

[numthreads(NUM_THREADS_X, NUM_THREADS_Y, 1)]
void CSMain(uint2 dispatchThreadId: SV_DispatchThreadID, uint groupIndex: SV_GroupIndex)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);

    luminanceHistogramShared[groupIndex] = 0;

    GroupMemoryBarrierWithGroupSync();

    if (input.cellCoord.x < uInputTextureDimensions.x && 
        input.cellCoord.y < uInputTextureDimensions.y)
    {
        float3 color = lastSceneHDRTex[input.cellCoord].rgb;
        float luminance = RGBToLuminance(color) / max(exposureInfoBuffer[0].Exposure, EPS_9);

        if (luminance > EPS_9)
        {
            const float tLum = (log(luminance) - minLuminanceLog) * invLuminanceRange;
            const float tBin = clamp(tLum, 0, 1);
            const int bin = uint(tBin * (NUM_NON_ZERO_BINS + 1));
            InterlockedAdd(luminanceHistogramShared[bin], 1);
        }
        else
        {
            InterlockedAdd(luminanceHistogramShared[0], 1);
        }
    }

    GroupMemoryBarrierWithGroupSync();

    InterlockedAdd(luminanceHistogram[groupIndex], luminanceHistogramShared[groupIndex]);
}

//---------------------------------------------------------------------------//