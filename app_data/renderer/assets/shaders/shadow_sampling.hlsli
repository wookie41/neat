#include "resources.hlsli"

//---------------------------------------------------------------------------//

float SampleSimpleDirectionalLightShadow(in float3 positionWS, in float3 positionVS, in float3 normalWS)
{
    const float pixelZ = -positionVS.z;

    int cascadeIndex = 0;
    while (pixelZ > uPerFrame.ShadowCascades[cascadeIndex].Split && cascadeIndex < (uPerFrame.NumShadowCascades - 1))
        cascadeIndex++;

    const float2 texelSize = float2((1.0 / 2048.0).xx);

    const float bias = max(0.05 * (1.0 - dot(normalWS, normalize(-uPerFrame.Sun.DirectionWS))), 0.005);
    const float4 positionLS = mul(uPerFrame.ShadowCascades[cascadeIndex].LightMatrix, float4(positionWS, 1));

    const float2 uv = positionLS.xy;
    
    const float depthPixel = clamp(positionLS.z + bias, 0, 1);
    const float depthShadowMap = gCascadeShadowTextures[cascadeIndex].SampleLevel(uLinearClampToBorderSampler, uv, 0).r;
    
    return depthPixel >= depthShadowMap ? 1 : 0;
}

//---------------------------------------------------------------------------//

float3 GetCascadeDebugColor(in int cascadeIndex)
{
    float3 cascadeColors[MAX_SHADOW_CASCADES] = {
        float3(1, 0, 0),
        float3(0, 1, 0),
        float3(0, 0, 1),
        float3(1, 1, 0),
        float3(0, 1, 1),
        float3(1, 0, 1),
    };

    return cascadeColors[cascadeIndex];
}