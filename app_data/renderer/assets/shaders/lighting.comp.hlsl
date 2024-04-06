#include "fullscreen_compute.hlsli"
#include "bindless.hlsli"
#include "uniforms.hlsli"
#include "packing.hlsli"

[[vk::binding(1, 0)]]
Texture2D<float4> gBufferColorTex : register(t0, space0);

[[vk::binding(2, 0)]]
Texture2D<float4> gBufferNormalsTex : register(t1, space0);

[[vk::binding(3, 0)]]
Texture2D<float4> gBufferParamsTex : register(t2, space0);

[[vk::binding(4, 0)]]
RWTexture2D<float4> outputImage : register(u0, space0);

[numthreads(8,8,1)]
void main(uint2 dispatchThreadId : SV_DispatchThreadID)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);

    float3 albedo = gBufferColorTex.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0).rgb;
    float3 normal = decodeNormal(gBufferNormalsTex.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0).xy);

    outputImage[input.cellCoord] = float4(albedo * max(dot(normal, -uPerFrame.Sun.DirectionWS), 0) * uPerFrame.Sun.Color, 1);
}