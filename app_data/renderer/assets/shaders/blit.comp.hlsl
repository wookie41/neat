#include "fullscreen_compute.hlsli"
#include "bindless.hlsli"

[[vk::binding(1, 0)]]
Texture2D<float4> inputImage : register(t0, space0);

[[vk::binding(2, 0)]]
RWTexture2D<float4> outputImage : register(u0, space0);

[numthreads(8,8,1)]
void main(uint2 dispatchThreadId : SV_DispatchThreadID)
{
    FullScreenComputeInput input = CreateFullScreenComputeArgs(dispatchThreadId);
    outputImage[input.cellCoord] = inputImage.SampleLevel(uLinearClampToEdgeSampler, input.uv, 0);

}