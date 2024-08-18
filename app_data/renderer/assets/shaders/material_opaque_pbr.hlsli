#ifndef MATERIAL_OPAQUE_PBR_H
#define MATERIAL_OPAQUE_PBR_H
//---------------------------------------------------------------------------//

#include "geometry_pass.hlsli"
#include "resources.hlsli"
#include "scene_types.hlsli"
#include "packing.hlsli"

//---------------------------------------------------------------------------//

void MaterialVertexShader(in MaterialVertexInput pVertexInput, inout Vertex pVertex)
{
}

//---------------------------------------------------------------------------//

void MaterialPixelShader(in MaterialPixelInput pMaterialInput, out MaterialPixelOutput pMaterialOutput)
{
    Material material = gMaterialsBuffer[pMaterialInput.materialInstanceIdx];

    const float3x3 TBN = float3x3(pMaterialInput.vertexTangent, pMaterialInput.vertexBinormal, pMaterialInput.vertexNormal);

    pMaterialOutput.albedo = sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.albedoTex).rgb;
    pMaterialOutput.normal = mul(decodeNormalMap(sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.normalTex)), TBN);
    pMaterialOutput.occlusion = material.occlusionTex == 0 ? 1 : sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.occlusionTex).r;
    pMaterialOutput.roughness = sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.roughnessTex).g;
    pMaterialOutput.metalness = sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.metalnessTex).b;
}

//---------------------------------------------------------------------------//

#endif // MATERIAL_OPAQUE_PBR_H
