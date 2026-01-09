#include "resources.hlsli"
#include "fullscreen.hlsli"

[[vk::binding(1, 0)]] Texture2D<float4> inputImage : register(t0, space0);

float4 PSMain(in FSInput pFragmentInput) : SV_Target0
{
    return pow(inputImage.Sample(uLinearClampToEdgeSampler, pFragmentInput.uv), 2.2);
}