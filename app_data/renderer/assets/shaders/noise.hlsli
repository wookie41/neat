#ifndef NOISE_H
#define NOISE_H

//---------------------------------------------------------------------------//

#include "resources.hlsli"

//---------------------------------------------------------------------------//

// https://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare/

float InterleavedGradientNoise(in int pX, in int pY)
{
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    float x = float(pX) + 5.588238f * float(uPerFrame.FrameIdMod64);
    float y = float(pY) + 5.588238f * float(uPerFrame.FrameIdMod64);
    return frac(magic.z * frac(dot(float2(x, y), magic.xy)));
}

//---------------------------------------------------------------------------//

float InterleavedGradientNoise(in float2 pixel, in int frame) {
    pixel += (float(frame) * 5.588238f);
    return frac(52.9829189f * frac(0.06711056f * float(pixel.x) + 0.00583715f * float(pixel.y)));
}

//---------------------------------------------------------------------------//

// Takes 2 noises in space [0..1] and remaps them in [-1..1]
float TriangularNoise(in float noise0, in float noise1)
{
    return noise0 + noise1 - 1.0f;
}

//---------------------------------------------------------------------------//

#endif // NOISE_H