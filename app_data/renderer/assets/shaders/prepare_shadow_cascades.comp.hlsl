//---------------------------------------------------------------------------//

// Calculation of the cascade planes based on
// https://developer.download.nvidia.com/SDK/10.5/opengl/src/cascaded_shadow_maps/doc/cascaded_shadow_maps.pdf


// Stabilization based on
// https://github.com/TheRealMJP/Shadows/blob/master/Shadows/SetupShadows.hlsl

//---------------------------------------------------------------------------//

#include "math.hlsli"
#include "resources.hlsli"
#include "scene_types.hlsli"

//---------------------------------------------------------------------------//

#define FIT_CASCADES 0x01
#define STABILIZE_CASCADES 0x02

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
cbuffer PrepareShadowCascadeParams : register(b0, space0)
{
    int numCascades;
    float splitFactor;
    float aspectRatio;
    float tanFovHalf;
    float shadowSamplingRadius;
    uint flags;
    float renderingDistance;
    float shadowMapSize;
}

[[vk::binding(1, 0)]]
StructuredBuffer<uint> minMaxDepthBuffer : register(t0, space0);

[[vk::binding(2, 0)]]
RWStructuredBuffer<ShadowCascade> lightMatrices : register(u0, space0);

//---------------------------------------------------------------------------//

float CalculateCascadeSplit(int cascadeIndex, float depthMinLinear, float depthMaxLinear)
{
    if (cascadeIndex < 0)
        return depthMinLinear;

    return depthMinLinear + ((depthMaxLinear - depthMinLinear) * (cascadeIndex + 1) / float(numCascades)); // linear

    
    // return lerp(
    //     depthMinLinear + (float(cascadeIndex + 1) / float(numCascades)) * (depthMaxLinear - depthMinLinear),
    //     depthMinLinear * pow(depthMaxLinear / depthMinLinear, float(cascadeIndex + 1) / float(numCascades)),
    //     .09);
}

//---------------------------------------------------------------------------//

[numthreads(MAX_SHADOW_CASCADES, 1, 1)]
void CSMain(uint localThreadIndex: SV_GroupIndex)
{
    if (localThreadIndex < numCascades)
    {
        const float depthMinLinear = (flags & FIT_CASCADES) > 0 ? -LinearizeDepth(asfloat(minMaxDepthBuffer[1]), uPerView.CameraNearPlane) : uPerView.CameraNearPlane;
        const float depthMaxLinear = (flags & FIT_CASCADES) > 0 ? -LinearizeDepth(asfloat(minMaxDepthBuffer[0]), uPerView.CameraNearPlane) : renderingDistance;

        const float nearSplit = CalculateCascadeSplit(int(localThreadIndex) - 1, depthMinLinear, depthMaxLinear);
        const float farSplit = CalculateCascadeSplit(localThreadIndex, depthMinLinear, depthMaxLinear);

        // Map Z component from [-1; 1] to [0; 1]
        float4x4 ndcCorrectionZ = {
            { 1.0f, 0.0f, 0.0f, 0.0f },
            { 0.0f, 1.0f, 0.0f, 0.0f },
            { 0.0f, 0.0f, -0.5f, 0.f },
            { 0.0f, 0.0f, 0.5f, 1.0f }
        };
        ndcCorrectionZ = transpose(ndcCorrectionZ);

        // Map NDC X and Y coordinates from [-1; 1] to [0;1] for shadow map sampling
        float4x4 textureSpaceConversion = {
            { 0.5, 0.0, 0.0, 0.0 },
            { 0.0, -0.5, 0.0, 0.0 },
            { 0.0, 0.0, 1.0, 0.0 },
            { 0.5, 0.5, 0.0, 1.0 },
        };
        textureSpaceConversion = transpose(textureSpaceConversion);

        // Calculate the view matrix for the light
        const float3 forward = -uPerFrame.Sun.DirectionWS;
        float3 up = abs(forward.y) < 0.9999 ? float3(0.0, -1.0, 0.0) : float3(0.0, 0.0, -1.0);
        const float3 right = normalize(cross(forward, up));
        up = normalize(cross(right, forward));

        float3 frustumPoints[8];
        float3 frustumCenter;

        // Calculate points of the view frustum capped to this cascade's near and far planes
        ComputeFrustumPoints(
            nearSplit, farSplit, aspectRatio, tanFovHalf, 
            uPerView.CameraPositionWS, uPerView.CameraForwardWS, uPerView.CameraUpWS,
            frustumPoints, frustumCenter);

        float4x4 view;
        view[0] = float4(right, 0);
        view[1] = float4(up, 0);
        view[2] = float4(forward, 0);
        view[3] = float4(0.xxx, 1.f);
        view = transpose(view);

        // Find the min and max point (bounding box) of this part of the frustum,
        // transform it to the POV of the light space and based on the build the projection matrix.
        float3 minP = float3(FLT_MAX.xxx);
        float3 maxP = float3(FLT_MIN.xxx);

        for (int i = 0; i < 8; ++i)
        {
            const float3 p = mul(view, float4(frustumPoints[i], 1.f)).xyz;
            minP = min(minP, p);
            maxP = max(maxP, p);
        }

        // Grow the area to make sure we don't sample outside of the shadow map
        minP -= shadowSamplingRadius * 2;
        maxP += shadowSamplingRadius * 2;

        const float3 scale = float3(2.xxx) / (maxP - minP);
        const float3 offset = -0.5 * (maxP + minP) * scale;

        float4x4 proj = float4x4(float4(0.xxxx), float4(0.xxxx), float4(0.xxxx), float4(0.xxxx));
        proj[0][0] = scale.x;
        proj[1][1] = scale.y;
        proj[2][2] = scale.z;
        proj[3][0] = offset.x;
        proj[3][1] = offset.y;
        proj[3][2] = offset.z;
        proj[3][3] = 1.f;
        proj = transpose(proj);

        if ((flags & STABILIZE_CASCADES) > 0)
        {
            const float4x4 shadowMatrix = mul(proj, view);
            float3 shadowOrigin = mul(shadowMatrix, float4(0.xxx, 1.0f)).xyz;
            shadowOrigin *= (shadowMapSize / 2.0f);

            float3 snappedOrigin = round(shadowOrigin);
            float3 snapOffset = snappedOrigin - shadowOrigin;
            snapOffset = snapOffset * (2.0f / shadowMapSize);

            proj[0][3] += snapOffset.x;
            proj[1][3] += snapOffset.y;
        }

        lightMatrices[localThreadIndex].RenderMatrix = mul(ndcCorrectionZ, mul(proj, view));
        lightMatrices[localThreadIndex].LightMatrix = mul(textureSpaceConversion, lightMatrices[localThreadIndex].RenderMatrix);
        lightMatrices[localThreadIndex].Split = farSplit;
        lightMatrices[localThreadIndex].OffsetScale = scale.xy;
    }
    else
    {
        lightMatrices[localThreadIndex].Split = 0;
        lightMatrices[localThreadIndex].OffsetScale = 0;
    }
}

//---------------------------------------------------------------------------//
