#include "bindless.hlsl"

struct FSInput {
    [[vk::location(0)]] float2 uv        : TEXCOORD0;
};

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
};

void main(in FSInput pFragmentInput, out FSOutput pFragmentOutput) {
#if (FEAT_TEST > 0)
    pFragmentOutput.color = sampleBindless(linearRepeatSampler, pFragmentInput.uv, 0) * float4(1, 0, 0, 1);
#else
    pFragmentOutput.color = sampleBindless(linearRepeatSampler, pFragmentInput.uv, 0);
#endif
}
