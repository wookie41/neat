#if (FEAT_MAT_DEFAULT > 0)

struct MaterialParams
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
};

#endif // FEAT_MAT_DEFAULT

[[vk::binding(3, 1)]]
StructuredBuffer<MaterialParams> gMaterialBuffer;
