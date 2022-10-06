struct FSInput {
    [[vk::location(0)]] float3 fragColor : FRAGCOLOR;
    [[vk::location(1)]] float2 uv        : TEXCOORD0;
};

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
};

[[vk::binding(1, 1), vk::combinedImageSampler]]
Texture2D<float4> gTexture;
[[vk::binding(5, 0), vk::combinedImageSampler]]
SamplerState linearRepeatSampler;

void main(in FSInput pFragmentInput, out FSOutput pFragmentOutput) {
    pFragmentOutput.color = gTexture.Sample(linearRepeatSampler, pFragmentInput.uv);
}
