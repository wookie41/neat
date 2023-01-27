#include "samplers.hlsl"

struct FSInput {
    [[vk::location(0)]] float2 uv        : TEXCOORD0;
};

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
};

[[vk::binding(1, 2)]]
Texture2D<float4> gTexture;

void main(in FSInput pFragmentInput, out FSOutput pFragmentOutput) {
    pFragmentOutput.color = gTexture.Sample(linearRepeatSampler, pFragmentInput.uv);
}
