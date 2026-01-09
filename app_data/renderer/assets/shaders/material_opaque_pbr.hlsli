#ifndef MATERIAL_OPAQUE_PBR_H
#define MATERIAL_OPAQUE_PBR_H

//---------------------------------------------------------------------------//


#include "common.hlsli"
#include "material_pass.hlsli"
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
    const float3 params = sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.occlusionTex).rgb;

    pMaterialOutput.albedo = sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.albedoTex).rgb;
    pMaterialOutput.normal = mul(decodeNormalMap(sampleBindless(uLinearRepeatSampler, pMaterialInput.uv, material.normalTex)), TBN);
    pMaterialOutput.occlusion = material.occlusionTex == 0 ? 1 : params.r;
    pMaterialOutput.roughness = params.g;
    pMaterialOutput.metalness = params.b;
    pMaterialOutput.motionVector = ComputeMotionVector(
        pMaterialInput.positionClip, 
        pMaterialInput.prevPositionClip, 
        float2(uPerView.CurrentView.JitterX, uPerView.CurrentView.JitterY), 
        float2(uPerView.PreviousView.JitterX, uPerView.PreviousView.JitterY)
    );
}

//---------------------------------------------------------------------------//

#endif // MATERIAL_OPAQUE_PBR_H
