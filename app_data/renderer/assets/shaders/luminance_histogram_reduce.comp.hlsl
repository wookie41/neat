//---------------------------------------------------------------------------//

#define NUM_THREADS_X 16
#define NUM_THREADS_Y 16
#define THREAD_GROUP_SIZE (NUM_THREADS_X * NUM_THREADS_Y)

//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "resources.hlsli"

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
cbuffer ReduceLuminanceHistogramParams : register(b0, space0)
{
    float minLuminanceLog;
    float logLuminanceRange;
    int totalPixelCount;
    float globalExposureOffset;
    float EV100SpeedPerSec;
    int3 _padding;
}

[[vk::binding(1, 0)]]
RWStructuredBuffer<uint> luminanceHistogram : register(u0, space0);

[[vk::binding(2, 0)]]
RWStructuredBuffer<ExposureInfo> exposureInfoBuffer : register(u1, space0);

groupshared float luminanceHistogramShared[THREAD_GROUP_SIZE];
groupshared uint countedPixels;

//---------------------------------------------------------------------------//

// reference: "Real-World Measurements forCall of Duty: Advanced Warfare"
float OffsetFromSceneEV(float sceneEV100) 
{
    float darkExp = 2.84f;
    float lightExp = 12.81f;

    float lightOffset = 1.47;
    float darkOffset = -3.17;

    float t = clamp((sceneEV100 - darkExp) / (lightExp - darkOffset), 0, 1);

    return lerp(darkOffset, lightOffset, t);
}

//---------------------------------------------------------------------------//

[numthreads(NUM_THREADS_X, NUM_THREADS_Y, 1)]
void CSMain(uint groupIndex: SV_GroupIndex)
{
    if (groupIndex == 0)
        countedPixels = 0;

    GroupMemoryBarrierWithGroupSync();

    InterlockedAdd(countedPixels, luminanceHistogram[groupIndex]);

    const float t = float(groupIndex) / float(THREAD_GROUP_SIZE - 1);
    const float lum = exp((minLuminanceLog + logLuminanceRange * t)) * luminanceHistogram[groupIndex];

    luminanceHistogramShared[groupIndex] = lum;
    luminanceHistogram[groupIndex] = 0; // Reset for next frame

    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (int cutoff = (THREAD_GROUP_SIZE >> 1); cutoff > 0; cutoff >>= 1)
    {
        if (groupIndex < cutoff)
            luminanceHistogramShared[groupIndex] += luminanceHistogramShared[groupIndex + cutoff];

        GroupMemoryBarrierWithGroupSync();
    }

    if (groupIndex == 0)
    {
        const float avgLum = luminanceHistogramShared[0] / float(countedPixels);

        const float lastEV100 = exposureInfoBuffer[0].EV100;
        const float sceneEV100 = ComputeEV100FromAvgLuminance(avgLum);

        const float exposureOffset = OffsetFromSceneEV(sceneEV100) + globalExposureOffset;

        const float targetEV100 = sceneEV100 - exposureOffset;
        const float deltaEV100 = targetEV100 - lastEV100;

        const float maxChangeEV100 = EV100SpeedPerSec * uPerFrame.DeltaTime;
        const float changeEV100 = sign(deltaEV100) * min(abs(deltaEV100), abs(maxChangeEV100));

        ExposureInfo exposureInfo;
        exposureInfo.AvgLum = avgLum;
        exposureInfo.EV100 = lastEV100 + changeEV100;
        exposureInfo.Exposure = ConvertEV100ToExposure(exposureInfo.EV100);

        exposureInfoBuffer[0] = exposureInfo;
    }
}

//---------------------------------------------------------------------------//