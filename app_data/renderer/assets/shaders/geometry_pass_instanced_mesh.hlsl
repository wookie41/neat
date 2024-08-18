#ifndef MATERIAL_PASS_INSTANCED_MESH_H
#define MATERIAL_PASS_INSTANCED_MESH_H

//---------------------------------------------------------------------------//

#include "scene_types.hlsli"
#include "resources.hlsli"
#include "geometry_pass.hlsli"
#include "packing.hlsli"

#include MATERIAL_PASS_VERTEX_H
#include MATERIAL_PASS_PIXEL_H

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
    float3 positionWS : POSITION_WS;
    [[vk::location(1)]]
    float2 uv : TEXCOORD0;
    [[vk::location(2)]]
    uint materialInstanceIdx : MATERIAL_INSTANCE_IDX;
    [[vk::location(3)]]
    float3 normal : NORMAL;
    [[vk::location(4)]]
    float3 tangent : TANGENT;
    [[vk::location(5)]]
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
    float4 positionWS : SV_Target3;
};

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer : register(t0, space0);

//---------------------------------------------------------------------------//

float4 VSMain(
    in VSInput pVertexInput, in uint pInstanceId: SV_INSTANCEID, out PSInput pPixelInput)
    : SV_Position
{
    MeshInstancedDrawInfo meshInstancedDrawInfo = gMeshInstancedDrawInfoBuffer[pInstanceId];

    float4x4 modelMatrix = gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].modelMatrix;
    float3 positionWS = mul(modelMatrix, float4(pVertexInput.position, 1.0)).xyz;

    // @TODO non-uniform scale support
    float3x3 normalMatrix = (float3x3)modelMatrix;

    // Write fragment input
    pPixelInput.positionWS = positionWS;
    pPixelInput.materialInstanceIdx = meshInstancedDrawInfo.materialInstanceIdx;
    pPixelInput.uv = pVertexInput.uv;
    pPixelInput.normal = normalize(mul(normalMatrix, pVertexInput.normal));
    pPixelInput.tangent = normalize(mul(normalMatrix, pVertexInput.tangent));
    pPixelInput.binormal = normalize(cross(pVertexInput.normal, pVertexInput.tangent));

    return mul(uPerView.ProjectionMatrix, mul(uPerView.ViewMatrix, float4(positionWS.xyz, 1)));
}

//---------------------------------------------------------------------------//

void PSMain(in PSInput pPixelInput, out PSOutput pPixelOutput)
{
    MaterialPixelInput materialPixelInput;
    materialPixelInput.uv = pPixelInput.uv;
    materialPixelInput.vertexNormal = pPixelInput.normal;
    materialPixelInput.vertexBinormal = pPixelInput.binormal;
    materialPixelInput.vertexTangent = pPixelInput.tangent;
    materialPixelInput.materialInstanceIdx = pPixelInput.materialInstanceIdx;

    MaterialPixelOutput materialPixelOutput;

    MaterialPixelShader(materialPixelInput, materialPixelOutput);

    pPixelOutput.color = float4(materialPixelOutput.albedo, 1);
    pPixelOutput.normals = float4(encodeNormal(materialPixelOutput.normal), encodeNormal(pPixelInput.normal));
    pPixelOutput.parameters = float4(materialPixelOutput.roughness, materialPixelOutput.metalness, materialPixelOutput.occlusion, 0);
    pPixelOutput.positionWS = float4(pPixelInput.positionWS, 1);
}

//---------------------------------------------------------------------------//

#endif // MATERIAL_PASS_INSTANCED_MESH_H



