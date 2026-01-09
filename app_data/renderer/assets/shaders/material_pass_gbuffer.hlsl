#ifndef GEOMETRY_PASS_GBUFFER_H
#define GEOMETRY_PASS_GBUFFER_H

//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "scene_types.hlsli"
#include "resources.hlsli"
#include "material_pass.hlsli"
#include "packing.hlsli"
#include "instanced_mesh.hlsli"

#include MATERIAL_PASS_INCLUDE

//---------------------------------------------------------------------------//

struct VSInput
{
    [[vk::location(0)]]
    float3 position : POSITION;
    [[vk::location(1)]]
    float2 uv : TEXCOORD0;
    [[vk::location(2)]]
    float3 normal : NORMAL;
    [[vk::location(3)]]
    float3 tangent : TANGENT;
};

//---------------------------------------------------------------------------//

struct PSInput
{
    [[vk::location(0)]]
    float4 positionClip : POSITION;
    [[vk::location(1)]]
    float4 prevPositionClip : PREV_POSITION;
    [[vk::location(2)]]
    float2 uv : TEXCOORD0;
    [[vk::location(3)]]
    uint materialInstanceIdx : MATERIAL_INSTANCE_IDX;
    [[vk::location(4)]]
    float3 normal : NORMAL;
    [[vk::location(5)]]
    float3 tangent : TANGENT;
    [[vk::location(6)]]
    float3 binormal : BINORMAL;
};

//---------------------------------------------------------------------------//

struct PSOutput
{
    [[vk::location(0)]]
    float4 color : SV_Target0;
    [[vk::location(1)]]
    float4 normals : SV_Target1;
    [[vk::location(2)]]
    float4 parameters : SV_Target2;
    [[vk::location(3)]]
    float2 motionVector : SV_Target3;
};

//---------------------------------------------------------------------------//

float4 VSMain(in VSInput pVertexInput, in uint pInstanceId: SV_INSTANCEID, out PSInput pPixelInput) : SV_Position
{
    const MeshInstancedDrawInfo meshInstancedDrawInfo = FetchMeshInstanceInfo(pInstanceId);

    const float4x4 modelMatrix = gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].modelMatrix;
    const float4x4 prevModelMatrix = gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].prevModelMatrix;

    const float3 positionWS = mul(modelMatrix, float4(pVertexInput.position, 1.0)).xyz;
    const float3 prevPositionWS = mul(prevModelMatrix, float4(pVertexInput.position, 1.0)).xyz;

    const float4 positionClip = mul(uPerView.CurrentView.ViewProjectionMatrix, float4(positionWS.xyz, 1));
    const float4 prevPositionClip = mul(uPerView.PreviousView.ViewProjectionMatrix, float4(prevPositionWS.xyz, 1));

    // @TODO non-uniform scale support
    const float3x3 normalMatrix = (float3x3)modelMatrix;

    // Write fragment input
    pPixelInput.positionClip = positionClip;
    pPixelInput.prevPositionClip = prevPositionClip;
    pPixelInput.materialInstanceIdx = meshInstancedDrawInfo.materialInstanceIdx;
    pPixelInput.uv = pVertexInput.uv;
    pPixelInput.normal = normalize(mul(normalMatrix, pVertexInput.normal));
    pPixelInput.tangent = normalize(mul(normalMatrix, pVertexInput.tangent));
    pPixelInput.binormal = normalize(cross(pVertexInput.normal, pVertexInput.tangent));

    return positionClip;
}

//---------------------------------------------------------------------------//

void PSMain(in PSInput pPixelInput, out PSOutput pPixelOutput)
{
    MaterialPixelInput materialPixelInput;
    materialPixelInput.uv = UnjitterUV(pPixelInput.uv, float2(uPerView.CurrentView.JitterX, uPerView.CurrentView.JitterY));
    materialPixelInput.vertexNormal = pPixelInput.normal;
    materialPixelInput.vertexBinormal = pPixelInput.binormal;
    materialPixelInput.vertexTangent = pPixelInput.tangent;
    materialPixelInput.materialInstanceIdx = pPixelInput.materialInstanceIdx;
    materialPixelInput.positionClip = pPixelInput.positionClip;
    materialPixelInput.prevPositionClip = pPixelInput.prevPositionClip;

    MaterialPixelOutput materialPixelOutput;

    MaterialPixelShader(materialPixelInput, materialPixelOutput);

    pPixelOutput.color = float4(materialPixelOutput.albedo, 1);
    pPixelOutput.normals = float4(encodeNormal(materialPixelOutput.normal), encodeNormal(pPixelInput.normal));
    pPixelOutput.parameters = float4(materialPixelOutput.roughness, materialPixelOutput.metalness, materialPixelOutput.occlusion, 0);    
    pPixelOutput.motionVector = materialPixelOutput.motionVector;
}

//---------------------------------------------------------------------------//

#endif // GEOMETRY_PASS_GBUFFER_H
