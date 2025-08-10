#ifndef GEOMETRY_PASS_SHADOWS_H
#define GEOMETRY_PASS_SHADOWS_H

//---------------------------------------------------------------------------//

struct CascadeShadowsUniformData
{
    int CascadeIndex;
    int3 _padding;
};

//---------------------------------------------------------------------------//

#include "scene_types.hlsli"
#include "resources.hlsli"
#include "material_pass.hlsli"
#include "packing.hlsli"
#include "instanced_mesh.hlsli"

#include MATERIAL_PASS_INCLUDE

//---------------------------------------------------------------------------//

[[vk::binding(1, 0)]] 
ConstantBuffer<CascadeShadowsUniformData> CascadeShadows : register(b0, space0);

[[vk::binding(2, 0)]]
StructuredBuffer<ShadowCascade> ShadowCascades : register(t0, space0);

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
};

//---------------------------------------------------------------------------//

struct PSOutput
{
};

//---------------------------------------------------------------------------//

float4 VSMain(in VSInput pVertexInput, in uint pInstanceId: SV_INSTANCEID, out PSInput pPixelInput) : SV_Position
{
    const MeshInstancedDrawInfo meshInstancedDrawInfo = FetchMeshInstanceInfo(pInstanceId);

    const float4x4 modelMatrix = gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].modelMatrix;
    const float3 positionWS = mul(modelMatrix, float4(pVertexInput.position, 1.0)).xyz;

    return mul(ShadowCascades[CascadeShadows.CascadeIndex].RenderMatrix, float4(positionWS.xyz, 1));
}

//---------------------------------------------------------------------------//

void PSMain(in PSInput pPixelInput, out PSOutput pPixelOutput)
{
}

//---------------------------------------------------------------------------//

#endif // GEOMETRY_PASS_SHADOWS_H


