#include "resources.hlsli"
#include "noise.hlsli"
#include "math.hlsli"

//---------------------------------------------------------------------------//

float SampleSimpleDirectionalLightShadow(in float3 positionWS, in float3 positionVS, in float3 normalWS, int2 svPosition, out int cascadeIndex)
{
    const float pixelZ = -positionVS.z;

    cascadeIndex = 0;
    while (pixelZ > uPerFrame.ShadowCascades[cascadeIndex].Split && cascadeIndex < (uPerFrame.NumShadowCascades - 1))
        cascadeIndex++;

    const float bias = max(0.05 * (1.0 - dot(normalWS, normalize(-uPerFrame.Sun.DirectionWS))), 0.005);
    const float4 positionLS = mul(uPerFrame.ShadowCascades[cascadeIndex].LightMatrix, float4(positionWS, 1));
    const float depthPixel = positionLS.z + bias;
    const float2 uv = positionLS.xy;
    
    // Spiral sampling pattern based on
    // https://github.com/playdeadgames/publications/blob/master/INSIDE/rendering_inside_gdc2016.pdf

    float occlusion = 0;
    float sampleCount = 12.f;

    float noise = InterleavedGradientNoise(svPosition.x, svPosition.y);

    float2 offsetScale = uPerFrame.ShadowCascades[cascadeIndex].OffsetScale * uPerFrame.Sun.ShadowSamplingRadius;

    for (int i = 0; i < sampleCount; i++) {

        float d = (i + 0.5f * noise) / sampleCount;
        d = sqrt(d);
        float angle = noise * 2 * MATH_PI + 2 * MATH_PI * i / sampleCount;

        float2 offset;
        sincos(angle, offset.x, offset.y);

        offset *= offsetScale * d;

        float2 samplePosition = uv + offset;

        const float depthShadowMap = gCascadeShadowTextures[cascadeIndex].SampleLevel(uNearestClampToBorderSampler, samplePosition, 0).r;

        occlusion += (depthPixel >= depthShadowMap ? 1 : 0);
    }

    return occlusion / sampleCount;
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

    //---------------------------------------------------------------------------//
