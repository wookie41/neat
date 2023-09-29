struct MaterialInstanceParams
{
    #if FEAT_ALBEDO_CONST_COLOR > 0
    float4 color;
    #endif

    #if FEAT_ALBEDO_TEX > 0
    uint albedoTexId;
    #endif
};

[[vk::binding(0, 1)]]
StructuredBuffer<MaterialInstanceParams> gMaterialBuffer_Dynamic;
