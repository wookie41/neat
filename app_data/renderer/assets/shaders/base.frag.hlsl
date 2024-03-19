#include "bindless.hlsli"
#include "uniforms.hlsli"
#include "materials.hlsli"
#include "base.hlsli"
#include "packing.hlsli"

struct FSOutput
{
    [[vk::location(0)]] float4 color : SV_Target0;
    [[vk::location(1)]] float4 normals : SV_Target1;
    [[vk::location(2)]] float2 parameters : SV_Target2;
};

void main(in FragmentInput pFragmentInput, out FSOutput pFragmentOutput)
{
    float3 albedo = sampleBindless(
                        uLinearRepeatSampler,
                        pFragmentInput.uv,
                        gMaterialBuffer[pFragmentInput.materialInstanceIdx].albedoTex)
                        .rgb;

    float3 normal = sampleBindless(
                        uLinearRepeatSampler,
                        pFragmentInput.uv,
                        gMaterialBuffer[pFragmentInput.materialInstanceIdx].normalTex)
                        .rgb;

    normal = normalize(normal.x * pFragmentInput.tangent.xyz +
                       normal.y * pFragmentInput.binormal +
                       normal.z * pFragmentInput.normal);

    pFragmentOutput.color = float4(albedo * max(dot(pFragmentInput.normal, -uPerFrame.Sun.DirectionWS) * uPerFrame.Sun.Color, 0), 1) ;
    pFragmentOutput.normals = float4(encodeNormal(normal), encodeNormal(pFragmentInput.normal));
}