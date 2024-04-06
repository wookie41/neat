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
    const float3 albedo = sampleBindless(
                        uLinearRepeatSampler,
                        pFragmentInput.uv,
                        gMaterialBuffer[pFragmentInput.materialInstanceIdx].albedoTex)
                        .rgb;

    float3 normal = decodeNormalMap(sampleBindless(
                        uLinearRepeatSampler,
                        pFragmentInput.uv,
                        gMaterialBuffer[pFragmentInput.materialInstanceIdx].normalTex));
    
    const float3x3 TBN = float3x3(pFragmentInput.tangent, pFragmentInput.binormal, pFragmentInput.normal);
    normal = mul(normal, TBN);

    pFragmentOutput.color = float4(albedo, 1);
    pFragmentOutput.normals = float4(encodeNormal(normal), encodeNormal(pFragmentInput.normal));
}

