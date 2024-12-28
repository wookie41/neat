#ifndef SCENE_TYPES_H
#define SCENE_TYPES_H

//---------------------------------------------------------------------------//

struct DirectionalLight
{
    float3 DirectionWS;
    float ShadowSamplingRadius;
    float3 Color;
    uint DebugDrawCascades;
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

struct ShadowCascade
{
    float4x4 LightMatrix;
    float Split;
    float OffsetScale;
    float2 _padding;
};

//---------------------------------------------------------------------------//

#define MATERIAL_FLAGS_HAS_ALBEDO_IMAGE_FLAG 0x1U
#define MATERIAL_FLAGS_HAS_NORMAL_IMAGE_FLAG 0x2U
#define MATERIAL_FLAGS_HAS_ROUGHNESS_IMAGE_FLAG 0x4U
#define MATERIAL_FLAGS_HAS_METALNESS_IMAGE_FLAG 0x8U
#define MATERIAL_FLAGS_HAS_OCCLUSION_IMAGE_FLAG 0x16U

struct Material
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

#endif // SCENE_TYPES_H