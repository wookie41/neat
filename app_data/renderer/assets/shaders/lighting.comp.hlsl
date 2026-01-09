//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "brdf.hlsli"
#include "fullscreen_compute.hlsli"
#include "math.hlsli"
#include "packing.hlsli"
#include "resources.hlsli"
#include "shadow_sampling.hlsli"
#include "volumetric_fog.hlsli"

//---------------------------------------------------------------------------//

// Inputs

[[vk::binding(1, 0)]]
StructuredBuffer<ExposureInfo> exposureBuffer : register(t0, space0);

[[vk::binding(2, 0)]]
Texture2D<float4> gBufferColorTex : register(t1, space0);

[[vk::binding(3, 0)]]
Texture2D<float4> gBufferNormalsTex : register(t2, space0);

[[vk::binding(4, 0)]]
Texture2D<float4> gBufferParamsTex : register(t3, space0);

[[vk::binding(5, 0)]]
Texture2D<float> depthTex : register(t4, space0);

[[vk::binding(6, 0)]]
Texture2D<float> gCascadeShadowTextures[] : register(t5, space0);

[[vk::binding(7, 0)]]
StructuredBuffer<ShadowCascade> gShadowCascades : register(t6, space0);

[[vk::binding(8, 0)]]
Texture3D<float4> gVolumetricFog : register(t7, space0);

// Outputs 
[[vk::binding(9, 0)]]
RWTexture2D<float4> outputImage : register(u0, space0);

//---------------------------------------------------------------------------//

[numthreads(8, 8, 1)]
void CSMain(uint2 dispatchThreadId: SV_DispatchThreadID)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);

    const float3 albedo = gBufferColorTex[input.cellCoord].rgb;

    const float3 normalWS = decodeNormal(gBufferNormalsTex[input.cellCoord].xy);
    const float3 parameters = gBufferParamsTex[input.cellCoord].rgb;

    const float linearRoughness = parameters.r;
    const float alphaRoughness = max(linearRoughness * linearRoughness, EPS_9);
    const float metalness = parameters.g;
    const float occlusion = parameters.b;

    const float depth = depthTex[input.cellCoord].x;
    const float3 posWS = UnprojectDepthToWorldPos(input.uv, depth, uPerView.CurrentView.InvViewProjMatrix);
    const float3 posVS = mul(uPerView.CurrentView.ViewMatrix, float4(posWS, 1)).xyz;

    int cascadeIndex;
    const float directionalLightShadow = SampleDirectionalLightShadow(gCascadeShadowTextures, gShadowCascades, posWS, posVS, input.cellCenter, cascadeIndex);

    const float3 V = normalize(uPerView.CurrentView.CameraPositionWS - posWS);
    const float3 L = -uPerFrame.Sun.DirectionWS;
    const float3 H = normalize(V + L);

    const float NdotV = max(dot(normalWS, V), 0.0001);
    const float NdotH = max(dot(normalWS, H), 0);
    const float NdotL = max(dot(normalWS, L), 0);
    const float LdotH = max(dot(L, H), 0);
    const float VdotH = max(dot(V, H), 0);

    const float sunStrengthExposed = uPerFrame.Sun.Strength * exposureBuffer[0].Exposure;
    const float3 directLighting = NdotL * uPerFrame.Sun.Color * directionalLightShadow;

    // Diffuse BRDF
    const float3 diffuseColor = albedo * (1 - metalness);
    const float disneyDiffuse = DisneyDiffuseRenormalized(NdotV, NdotL, LdotH, linearRoughness);
    const float3 diffuseDirect = diffuseColor * disneyDiffuse * MATH_PI_RCP * directLighting;

    // Specular BRDF
    const float3 specularColor = lerp(0.04, albedo, metalness);
    const float3 F = F_Schlick(specularColor, VdotH);
    const float Vis = V_SmithGGXCorrelated(NdotL, NdotV, alphaRoughness);
    const float D = D_GGX(NdotH, alphaRoughness);
    const float3 specularDirect = D * F * Vis  * directLighting;

    const float3 ambientTerm = 0.006 * diffuseColor;

    float3 pixelColor = (diffuseDirect + specularDirect + ambientTerm) * sunStrengthExposed;
    
    if (uPerFrame.Sun.DebugDrawCascades > 0)
    {
        pixelColor *= GetCascadeDebugColor(cascadeIndex);
    }

    pixelColor = ApplyVolumetricFog(input.uv, depth, pixelColor, gVolumetricFog);

    outputImage[input.cellCoord] = float4(pixelColor, 1);
}
//---------------------------------------------------------------------------//