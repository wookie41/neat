//---------------------------------------------------------------------------//

#define A_GPU 1
#define A_HLSL 1
#define SPD_NO_WAVE_OPERATIONS 1

//---------------------------------------------------------------------------//

#include "ffx/ffx_a.h"
#include "fullscreen_compute.hlsli"

//---------------------------------------------------------------------------//

struct SpdGlobalAtomicBufferData
{
    uint counter[6];
};

//---------------------------------------------------------------------------//

[[vk::binding(1, 0)]]
cbuffer BuildHiZParams : register(b1, space0)
{
    uint2 uHiZBufferDimensions;
    int uNumMips;
    int uWorkGroupCount;
}

[[vk::binding(2, 0)]]
RWStructuredBuffer<SpdGlobalAtomicBufferData> spdGlobalAtomicBuffer : register(u0, space0);

[[vk::binding(3, 0)]]
Texture2D depthTex : register(t0, space0);

[[vk::binding(4, 0)]]
RWTexture2D<float> hiZBufferTex[12] : register(u1, space0);

//---------------------------------------------------------------------------//

groupshared AU1 spd_counter;
groupshared AF1 spd_intermediate[16][16];

//---------------------------------------------------------------------------//

AF4 SpdLoadSourceImage(ASU2 p, AU1 slice)
{
    // Bounds check
    if (p.x >= uInputTextureDimensions.x || p.y >= uInputTextureDimensions.y)
    {
        return AF4_x(1);
    }

    bool sampleExtraColumn = ((uInputTextureDimensions.x & 1) != 0);
    bool sampleExtraRow = ((uInputTextureDimensions.y & 1) != 0);

    float maxDepth = depthTex[min(p, uInputTextureDimensions - 1)].r;

    // if we are reducing an odd-sized texture, we need to fetch additional texels
    if (sampleExtraColumn)
    {
        maxDepth = max(maxDepth, depthTex[min(p + ASU2(2, 0), uInputTextureDimensions - 1)].r);
        maxDepth = max(maxDepth, depthTex[min(p + ASU2(2, 1), uInputTextureDimensions - 1)].r);
    }

    if (sampleExtraRow)
    {
        maxDepth = max(maxDepth, depthTex[min(p + ASU2(0, 2), uInputTextureDimensions - 1)].r);
        maxDepth = max(maxDepth, depthTex[min(p + ASU2(1, 2), uInputTextureDimensions - 1)].r);
    }

    // if both edges are odd, include the corner texel
    if (sampleExtraColumn && sampleExtraRow)
    {
        maxDepth = max(maxDepth, depthTex[min(p + ASU2(2, 2), uInputTextureDimensions - 1)].r);
    }

    return AF4_x(maxDepth);
}

//---------------------------------------------------------------------------//

AF4 SpdLoad(ASU2 p, AU1 slice)
{
    const int2 mipSize = uInputTextureDimensions.xy >> 5;

    if (p.x >= mipSize.x || p.y >= mipSize.y)
    {
        return AF4_x(0);
    }

    float maxDepth = hiZBufferTex[5][min(p, uInputTextureDimensions - 1)].r;

    bool sampleExtraColumn = ((mipSize.x & 1) != 0);
    bool sampleExtraRow = ((mipSize.y & 1) != 0);

    // if we are reducing an odd-sized texture, we need to fetch additional texels
    if (sampleExtraColumn)
    {
        maxDepth = max(maxDepth, hiZBufferTex[5][min(p + int2(2, 0), mipSize - 1)].r);
        maxDepth = max(maxDepth, hiZBufferTex[5][min(p + int2(2, 1), mipSize - 1)].r);
    }
    if (sampleExtraRow)
    {
        maxDepth = max(maxDepth, hiZBufferTex[5][min(p + int2(0, 2), mipSize - 1)].r);
        maxDepth = max(maxDepth, hiZBufferTex[5][min(p + int2(1, 2), mipSize - 1)].r);
    }
    // if both edges are odd, include the corner texel
    if (sampleExtraColumn && sampleExtraRow)
    {
        maxDepth = max(maxDepth, hiZBufferTex[5][min(p + int2(2, 2), mipSize - 1)].r);
    }

    return AF4(maxDepth.xxxx);
} // load from output MIP 5

//---------------------------------------------------------------------------//

void SpdStore(ASU2 p, AF4 value, AU1 mip, AU1 slice)
{
    uint2 mipSize = uHiZBufferDimensions.xy >> mip;
    mipSize = max(mipSize, uint2(1, 1));

    if (p.x >= mipSize.x || p.y >= mipSize.y)
    {
        return;
    }

    hiZBufferTex[mip][p] = value.x;
}

//---------------------------------------------------------------------------//

void SpdIncreaseAtomicCounter(AU1 slice)
{
    InterlockedAdd(spdGlobalAtomicBuffer[0].counter[slice], 1, spd_counter);
}

//---------------------------------------------------------------------------//

AU1 SpdGetAtomicCounter()
{
    return spd_counter;
}

//---------------------------------------------------------------------------//

void SpdResetAtomicCounter(AU1 slice)
{
    spdGlobalAtomicBuffer[0].counter[slice] = 0;
}

//---------------------------------------------------------------------------//

AF4 SpdLoadIntermediate(AU1 x, AU1 y)
{
    return spd_intermediate[x][y];
}

//---------------------------------------------------------------------------//

void SpdStoreIntermediate(AU1 x, AU1 y, AF4 value)
{
    spd_intermediate[x][y] = value.x;
}

//---------------------------------------------------------------------------//

AF4 SpdReduce4(AF4 v0, AF4 v1, AF4 v2, AF4 v3)
{
    return AF4_x(max(v0.x, max(v1.x, max(v2.x, v3.x))));
}

//---------------------------------------------------------------------------//

#include "ffx/ffx_spd.h"

//---------------------------------------------------------------------------//

[numthreads(256, 1, 1)]
void CSMain(uint2 dispatchThreadId: SV_DispatchThreadID, uint3 workGroupId: SV_GroupID, uint localThreadIndex: SV_GroupIndex)
{
    SpdDownsample(
        AU2(workGroupId.xy),
        AU1(localThreadIndex),
        AU1(uNumMips),
        AU1(uWorkGroupCount),
        AU1(workGroupId.z),
        AU2(0, 0));
}

//---------------------------------------------------------------------------//