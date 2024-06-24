#include "base.hlsli"
#include "bindless.hlsli"
#include "materials.hlsli"
#include "packing.hlsli"
#include "uniforms.hlsli"

struct FSOutput
{
    [[vk::location(0)]]
    float4 color : SV_Target0;
    [[vk::location(1)]]
    float4 normals : SV_Target1;
    [[vk::location(2)]]
    float4 parameters : SV_Target2;
    [[vk::location(3)]]
    float4 positionWS : SV_Target3;
};

void main(in FragmentInput pFragmentInput, out FSOutput pFragmentOutput)
{
    MaterialParams materialParams = gMaterialBuffer[pFragmentInput.materialInstanceIdx];

    const float3 albedo = sampleBindless(
                              uLinearRepeatSampler,
                              pFragmentInput.uv,
                              materialParams.albedoTex)
                              .rgb;

    float3 normal = decodeNormalMap(sampleBindless(
        uLinearRepeatSampler,
        pFragmentInput.uv,
        materialParams.normalTex));

    const float occlusion = materialParams.occlusionTex == 0 ? 1 : sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, materialParams.occlusionTex).r;
    const float roughness = sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, materialParams.roughnessTex).g;
    const float metalness = sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, materialParams.metalnessTex).b;

    const float3x3 TBN = float3x3(pFragmentInput.tangent, pFragmentInput.binormal, pFragmentInput.normal);
    normal = mul(normal, TBN);

    pFragmentOutput.color = float4(albedo, 1);
    pFragmentOutput.normals = float4(encodeNormal(normal), encodeNormal(pFragmentInput.normal));
    pFragmentOutput.parameters = float4(roughness, metalness, occlusion, 0);
    pFragmentOutput.positionWS = float4(pFragmentInput.positionWS, 1);
}   
