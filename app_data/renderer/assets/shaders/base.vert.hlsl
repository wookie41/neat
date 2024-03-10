#include "bindless.hlsli"
#include "constant_buffers.hlsli"
#include "base.hlsli"

struct MeshInstancedDrawInfo
{
    uint meshInstanceIdx;
    uint materialInstanceIdx;
};

struct MeshInstanceInfo
{
    float4x4 modelMatrix;
};

[[vk::binding(2, 1)]]
StructuredBuffer<MeshInstanceInfo> gMeshInstanceInfoBuffer;

[[vk::binding(4, 1)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer;

struct VSInput {
    [[vk::location(0)]] float3 position  : POSITION; 
    [[vk::location(1)]] float2 uv        : TEXCOORD0;
    [[vk::location(2)]] float3 normal    : NORMAL;
    [[vk::location(3)]] float3 tangent   : TANGENT;
};

float4 main(
        in VSInput pVertexInput, 
        in uint pInstanceId : SV_INSTANCEID,
        out FragmentInput pFragmentInput) : SV_Position {

    MeshInstancedDrawInfo meshInstancedDrawInfo = gMeshInstancedDrawInfoBuffer[pInstanceId];
    pFragmentInput.materialInstanceIdx = meshInstancedDrawInfo.materialInstanceIdx;
    pFragmentInput.uv = pVertexInput.uv;
    return mul(uPerView.proj, 
        mul(uPerView.view, 
        mul(gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].modelMatrix, 
        float4(pVertexInput.position, 1.0))));
}