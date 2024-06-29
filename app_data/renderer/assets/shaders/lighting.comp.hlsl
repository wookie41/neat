#include "bindless.hlsli"
#include "brdf.hlsli"
#include "fullscreen_compute.hlsli"
#include "math.hlsli"
#include "packing.hlsli"
#include "uniforms.hlsli"


[[vk::binding(1, 0)]]
Texture2D<float4> gBufferColorTex : register(t0, space0);

[[vk::binding(2, 0)]]
Texture2D<float4> gBufferNormalsTex : register(t1, space0);

[[vk::binding(3, 0)]]
Texture2D<float4> gBufferParamsTex : register(t2, space0);

[[vk::binding(4, 0)]]
Texture2D<float4> postionWSTex : register(t3, space0);

[[vk::binding(5, 0)]]
Texture2D<float4> depthTex : register(t4, space0);

[[vk::binding(6, 0)]]
RWTexture2D<float4> outputImage : register(u0, space0);

[numthreads(8, 8, 1)]
void main(uint2 dispatchThreadId: SV_DispatchThreadID)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);

    const float3 albedo = gBufferColorTex.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0).rgb;
    const float3 normal = decodeNormal(gBufferNormalsTex.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0).xy);
    const float3 parameters = gBufferParamsTex.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0).rgb;

    const float roughness = parameters.r;
    const float metalness = parameters.g;
    const float occlusion = parameters.b;

    const float depth = depthTex.SampleLevel(uNearestClampToEdgeSampler, input.uv, 0).x;
    // const float3 posWS = UnprojectDepthToWorldPos(input.uv, depth, uPerView.InvViewProjMatrix);
    const float3 posWS = postionWSTex.SampleLevel(uNearestClampToEdgeSampler, input.uv, 0).xyz;

    const float3 V = normalize(uPerView.CameraPositionWS - posWS);
    const float3 L = -uPerFrame.Sun.DirectionWS;
    const float3 H = normalize(V + L);

    const float NdotV = max(dot(normal, V), 0.0001);
    const float NdotH = max(dot(normal, H), 0);
    const float NdotL = max(dot(normal, L), 0);
    const float LdotH = max(dot(L, H), 0);
    const float VdotH = max(dot(V, H), 0);

    // Diffuse BRDF
    const float fd = DisneyDiffuseRenormalized(NdotV, NdotL, LdotH, roughness);

    // @TODO add in the divide by PI once we have physical light units for the directional light
    const float3 diffuse = fd * albedo * (1 - metalness) * occlusion * uPerFrame.Sun.Color;

    // Specular BRDF
    const float3 specularColor = lerp(0.04, albedo, metalness);
    const float3 F = F_Schlick(specularColor, VdotH);
    const float Vis = V_SmithGGXCorrelated(NdotL, NdotV, roughness);
    const float D = D_GGX(NdotH, roughness);
    const float3 specular = D * F * Vis;

    outputImage[input.cellCoord] = float4((diffuse + specular) * NdotL, 1);
}
