[[vk::binding(0, 2)]]
SamplerState uNearestClampToEdgeSampler;
[[vk::binding(1, 2)]]
SamplerState uNearestClampToBorderSampler;
[[vk::binding(2, 2)]]
SamplerState uNearestRepeatSampler;
[[vk::binding(3, 2)]]
SamplerState uLinearClampToEdgeSampler;
[[vk::binding(4, 2)]]
SamplerState uLinearClampToBorderSampler;
[[vk::binding(5, 2)]]
SamplerState uLinearRepeatSampler;

[[vk::binding(6, 2)]]
Texture2D uTextures2D[2048];

float4 sampleBindless(in SamplerState samplerState, in float2 uv, in uint textureId) {
    return uTextures2D[textureId].Sample(samplerState, uv);
}