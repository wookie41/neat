//---------------------------------------------------------------------------//

#include "bindless.hlsli"
#include "materials.hlsli"
#include "packing.hlsli"
#include "uniforms.hlsli"

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

struct FSInput
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

//---------------------------------------------------------------------------//

struct MeshInstancedDrawInfo
{
    uint meshInstanceIdx;
    uint materialInstanceIdx;
};

//---------------------------------------------------------------------------//

struct MeshInstanceInfo
{
    float4x4 modelMatrix;
};

//---------------------------------------------------------------------------//

struct DefaultMaterial
{
    float3 albedo;
    uint albedoTex;
    float3 normal;
    uint normalTex;
    float roughness;
    float metalness;
    float occlusion;
    uint roughnessTex;
    uint metalnessTex;
    uint occlusionTex;
    uint flags;
    uint _padding;
};

//---------------------------------------------------------------------------//

[[vk::binding(2, 1)]]
StructuredBuffer<MeshInstanceInfo> gMeshInstanceInfoBuffer;

[[vk::binding(4, 1)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer;

[[vk::binding(3, 1)]]
ByteAddressBuffer gMaterialsBuffer;

//---------------------------------------------------------------------------//

float4 VSMain(
    in VSInput pVertexInput,
    in uint pInstanceId: SV_INSTANCEID,
    out FSInput pFragmentInput)
    : SV_Position
{
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

//---------------------------------------------------------------------------//

void FSMain(in FSInput pFragmentInput, out FSOutput pFragmentOutput)
{
    DefaultMaterial material = gMaterialsBuffer.Load<DefaultMaterial>(pFragmentInput.materialInstanceIdx * sizeof(DefaultMaterial));

    const float3 albedo = sampleBindless(
                              uLinearRepeatSampler,
                              pFragmentInput.uv,
                              material.albedoTex)
                              .rgb;

    float3 normal = decodeNormalMap(sampleBindless(
        uLinearRepeatSampler,
        pFragmentInput.uv,
        material.normalTex));

    const float occlusion = material.occlusionTex == 0 ? 1 : sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, material.occlusionTex).r;
    const float roughness = sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, material.roughnessTex).g;
    const float metalness = sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, material.metalnessTex).b;

    const float3x3 TBN = float3x3(pFragmentInput.tangent, pFragmentInput.binormal, pFragmentInput.normal);
    normal = mul(normal, TBN);

    pFragmentOutput.color = float4(albedo, 1);
    pFragmentOutput.normals = float4(encodeNormal(normal), encodeNormal(pFragmentInput.normal));
    pFragmentOutput.parameters = float4(roughness, metalness, occlusion, 0);
    pFragmentOutput.positionWS = float4(pFragmentInput.positionWS, 1);
}

//---------------------------------------------------------------------------//
