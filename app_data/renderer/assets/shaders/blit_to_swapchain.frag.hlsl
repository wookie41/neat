#include "fullscreen.hlsli"
#include "bindless.hlsli"

[[vk::binding(0, 0)]] Texture2D<float4> inputImage : register(t0, space0);

float4 main(in FragmentInput pFragmentInput) : SV_Target0
{
    return pow(inputImage.Sample(uLinearClampToEdgeSampler, pFragmentInput.uv), 2.2);
}