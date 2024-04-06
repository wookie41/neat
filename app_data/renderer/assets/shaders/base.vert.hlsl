#include "bindless.hlsli"
#include "uniforms.hlsli"
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
    
    float4x4 modelMatrix = gMeshInstanceInfoBuffer[meshInstancedDrawInfo.meshInstanceIdx].modelMatrix;
    float3 positionWS = mul(modelMatrix, float4(pVertexInput.position, 1.0)).xyz;

    // @TODO non-uniform scale support
    float3x3 normalMatrix = (float3x3)modelMatrix;

    // Write fragment input
    pFragmentInput.positionWS = positionWS;
    pFragmentInput.materialInstanceIdx = meshInstancedDrawInfo.materialInstanceIdx;
    pFragmentInput.uv = pVertexInput.uv;
    pFragmentInput.normal = normalize(mul(normalMatrix, pVertexInput.normal));
    pFragmentInput.tangent = normalize(mul(normalMatrix, pVertexInput.tangent));
    pFragmentInput.binormal = normalize(cross(pFragmentInput.normal, pFragmentInput.tangent));

    return mul(uPerView.ProjectionMatrix, mul(uPerView.ViewMatrix, float4(positionWS.xyz, 1)));
}

