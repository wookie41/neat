#ifndef VOLUMETRIC_FOG_H
#define VOLUMETRIC_FOG_H

//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "math.hlsli"
#include "resources.hlsli"

//---------------------------------------------------------------------------//

float3 ApplyVolumetricFog(
    in float2 screnUV, in float rawDepth, float3 color,
    in Texture3D<float4> volumetricFogTexture)
{
    const float linearDepth = LinearizeDepth(rawDepth, uPerView.CurrentView.CameraNearPlane);
    const float depthUV = LinearDepthToUV(uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar, linearDepth, uPerFrame.VolumetricFogDimensions.z);
    const float3 froxelUVW = float3(screnUV.xy, depthUV);
    const float4 scatteringTransmittance = volumetricFogTexture.Sample(uLinearClampToEdgeSampler, froxelUVW);

    const float scatteringModifier = (uPerFrame.VolumetricFogOpacityAAEnabled > 0) ? max(1 - scatteringTransmittance.a, EPS_9) : 1.0;
    color.rgb = color.rgb * scatteringTransmittance.a + scatteringTransmittance.rgb * scatteringModifier;

    return color;
}

//---------------------------------------------------------------------------//

#endif // VOLUMETRIC_FOG_H