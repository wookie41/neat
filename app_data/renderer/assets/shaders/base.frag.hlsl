#include "./bindless.incl.hlsl"
#include "./constant_buffers.incl.hlsl"
#include "./materials.incl.hlsl"

struct FSInput {
    [[vk::location(0)]] float2 uv        : TEXCOORD0;
};

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
};

void main(in FSInput pFragmentInput, out FSOutput pFragmentOutput) {
    pFragmentOutput.color = pow(sampleBindless(uLinearRepeatSampler, pFragmentInput.uv, gMaterialBuffer[0].albedoTex), 2.2);
}