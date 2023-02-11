[[vk::binding(0, 0)]]
SamplerState nearestClampToEdgeSampler;
[[vk::binding(1, 0)]]
SamplerState nearestClampToBorderSampler;
[[vk::binding(2, 0)]]
SamplerState nearestRepeatSampler;
[[vk::binding(3, 0)]]
SamplerState linearClampToEdgeSampler;
[[vk::binding(4, 0)]]
SamplerState linearClampToBorderSampler;
[[vk::binding(5, 0)]]
SamplerState linearRepeatSampler;


[[vk::binding(6, 0)]]
Texture2D uTextures2D[2048];

