#if (FEAT_MAT_DEFAULT > 0)

struct MaterialParams
{
    uint flags;
    float3 albedo;
    float3 normal;
    float roughness;
    float metalness;
    float occlusion;
    uint albedoTex;
    uint normalTex;
    uint roughnessTex;
    uint metalnessTex
    uint occlusionTex;
};

#endif // FEAT_MAT_DEFAULT

[[vk::binding(0, 1)]]
StructuredBuffer<MaterialParams> gMaterialBuffer;
