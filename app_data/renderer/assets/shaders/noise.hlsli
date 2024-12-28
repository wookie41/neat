#ifndef NOISE_H
#define NOISE_H

//---------------------------------------------------------------------------//

#include "resources.hlsli"

//---------------------------------------------------------------------------//

// https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/

float InterleavedGradientNoise(int pX, int pY)
{
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    float x = float(pX) + 5.588238f * float(uPerFrame.FrameIdMod64);
    float y = float(pY) + 5.588238f * float(uPerFrame.FrameIdMod64);
    return frac(magic.z * frac(dot(float2(x, y), magic.xy)));
}

//---------------------------------------------------------------------------//

#endif // NOISE_H