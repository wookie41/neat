//---------------------------------------------------------------------------//

#include "scene_types.hlsli"

//---------------------------------------------------------------------------//

struct PerView
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 InvViewProjMatrix;
    float3 CameraPositionWS;
};

//---------------------------------------------------------------------------//

struct PerFrame
{
    DirectionalLight Sun;
};

//---------------------------------------------------------------------------//

// NOTE: space/descriptor set 0 is reserved for any custom bindings,
// e.g. input/output storage images for compute tasks

//---------------------------------------------------------------------------//

[[vk::binding(0, 1)]] ConstantBuffer<PerFrame> uPerFrame : register(b0, space1);

[[vk::binding(1, 1)]] ConstantBuffer<PerView> uPerView : register(b1, space1);

//---------------------------------------------------------------------------//

[[vk::binding(0, 2)]]
StructuredBuffer<MeshInstanceInfo> gMeshInstanceInfoBuffer : register(t1, space2);

[[vk::binding(1, 2)]]
StructuredBuffer<Material> gMaterialsBuffer : register(t2, space2);

//---------------------------------------------------------------------------//

[[vk::binding(0, 3)]]
Texture2D uTextures2D[2048] : register(t0, space2);

[[vk::binding(1, 3)]]
SamplerState uNearestClampToEdgeSampler : register(s0, space3);
[[vk::binding(2, 3)]]
SamplerState uNearestClampToBorderSampler : register(s1, space3);
[[vk::binding(3, 3)]]
SamplerState uNearestRepeatSampler : register(s2, space3);
[[vk::binding(4, 3)]]
SamplerState uLinearClampToEdgeSampler : register(s3, space3);
[[vk::binding(5, 3)]]
SamplerState uLinearClampToBorderSampler : register(s4, space3);
[[vk::binding(6, 3)]]
SamplerState uLinearRepeatSampler : register(s5, space3);

//---------------------------------------------------------------------------//

float4 sampleBindless(in SamplerState samplerState, in float2 uv, in uint textureId) {
    return uTextures2D[textureId].Sample(samplerState, uv);
}

//---------------------------------------------------------------------------//
