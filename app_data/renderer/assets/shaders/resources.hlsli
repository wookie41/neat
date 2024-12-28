#ifndef RESOURCES_H
#define RESOURCES_H

//---------------------------------------------------------------------------//

#include "scene_types.hlsli"

//---------------------------------------------------------------------------//

#define MAX_SHADOW_CASCADES 6 // Keep in sync with renderer_render_task_cascade_shadows.odin

//---------------------------------------------------------------------------//

struct PerView
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 InvViewProjMatrix;
    float4x4 InvProjMatrix;
    float3 CameraPositionWS;
    float _padding0;
    float3 CameraForwardWS;
    float _padding1;
};

//---------------------------------------------------------------------------//

struct PerFrame
{
    DirectionalLight Sun;
    ShadowCascade ShadowCascades[MAX_SHADOW_CASCADES];
    int NumShadowCascades;
    int FrameIdMod2;
    int FrameIdMod4;
    int FrameIdMod16;
    int FrameIdMod64;
};

//---------------------------------------------------------------------------//

// NOTE: space/descriptor set 0 is reserved for any custom bindings,
// e.g. input/output storage images for compute tasks

//---------------------------------------------------------------------------//

[[vk::binding(0, 1)]] ConstantBuffer<PerFrame> uPerFrame : register(b0, space1);

[[vk::binding(1, 1)]] ConstantBuffer<PerView> uPerView : register(b1, space1);

//---------------------------------------------------------------------------//

[[vk::binding(0, 2)]]
StructuredBuffer<MeshInstanceInfo> gMeshInstanceInfoBuffer : register(t0, space2);

[[vk::binding(1, 2)]]
StructuredBuffer<Material> gMaterialsBuffer : register(t1, space2);

[[vk::binding(2, 2)]]
Texture2D gCascadeShadowTextures[MAX_SHADOW_CASCADES] : register(t2, space2);

//---------------------------------------------------------------------------//

[[vk::binding(0, 3)]]
Texture2D uTextures2D[2048] : register(t0, space3);

[[vk::binding(1, 3)]]
SamplerState uNearestClampToEdgeSampler : register(s1, space3);
[[vk::binding(2, 3)]]
SamplerState uNearestClampToBorderSampler : register(s2, space3);
[[vk::binding(3, 3)]]
SamplerState uNearestRepeatSampler : register(s3, space3);
[[vk::binding(4, 3)]]
SamplerState uLinearClampToEdgeSampler : register(s4, space3);
[[vk::binding(5, 3)]]
SamplerState uLinearClampToBorderSampler : register(s5, space3);
[[vk::binding(6, 3)]]
SamplerState uLinearRepeatSampler : register(s6, space3);

//---------------------------------------------------------------------------//

float4 sampleBindless(in SamplerState samplerState, in float2 uv, in uint textureId) {
    return uTextures2D[textureId].Sample(samplerState, uv);
}

//---------------------------------------------------------------------------//

#endif // RESOURCES_H