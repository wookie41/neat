[[vk::binding(0, 2)]]
SamplerState nearestClampToEdgeSampler;
[[vk::binding(1, 2)]]
SamplerState nearestClampToBorderSampler;
[[vk::binding(2, 2)]]
SamplerState nearestRepeatSampler;
[[vk::binding(3, 2)]]
SamplerState linearClampToEdgeSampler;
[[vk::binding(4, 2)]]
SamplerState linearClampToBorderSampler;
[[vk::binding(5, 2)]]
SamplerState linearRepeatSampler;


[[vk::binding(6, 2)]]
Texture2D uTextures2D[2048];


float4 sampleBindless(in SamplerState samplerState, in float2 uv, in uint textureId) {
    return uTextures2D[textureId].Sample(linearRepeatSampler, uv);
}