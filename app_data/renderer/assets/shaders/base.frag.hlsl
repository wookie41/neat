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

#if (FEAT_TEST > 0)
    pFragmentOutput.color = gTexture.Sample(linearRepeatSampler, pFragmentInput.uv) * float4(1, 0, 0, 1);
#else
    pFragmentOutput.color = gTexture.Sample(linearRepeatSampler, pFragmentInput.uv);
#endif
}
