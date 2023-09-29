#include "./bindless.incl.hlsl"
#include "./constant_buffers.incl.hlsl"

struct FSInput {
    [[vk::location(0)]] float2 uv        : TEXCOORD0;
};

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
};

void main(in FSInput pFragmentInput, out FSOutput pFragmentOutput) {
#if (FEAT_TEST > 0)
    pFragmentOutput.color = pow(sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, 0) * float4(1, 0, 0, 1), 2.2);
#else
    pFragmentOutput.color = pow(sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, 0), 2.2);
#endif
}
