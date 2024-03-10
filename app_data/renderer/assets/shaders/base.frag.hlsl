#include "bindless.hlsli"
#include "constant_buffers.hlsli"
#include "materials.hlsli"
#include "base.hlsli"

struct FSOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
    [[vk::location(1)]] float4 normals : SV_Target1;
    [[vk::location(2)]] float2 parameters : SV_Target2;
};

void main(in FragmentInput pFragmentInput, out FSOutput pFragmentOutput) {
    pFragmentOutput.color = sampleBindless(
        uLinearRepeatSampler, 
        pFragmentInput.uv, 
        gMaterialBuffer[pFragmentInput.materialInstanceIdx].albedoTex);
}