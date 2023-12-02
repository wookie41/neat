#include "./bindless.incl.hlsl"
#include "./constant_buffers.incl.hlsl"

struct VSInput {
    [[vk::location(0)]] float3 position  : POSITION; 
    [[vk::location(1)]] float2 uv        : TEXCOORD0;
    [[vk::location(2)]] float2 normal    : NORMAL;
    [[vk::location(3)]] float2 tangent   : TANGENT;
};

struct VSOutput {
    [[vk::location(0)]] float2 uv        : TEXCOORD0;
};

float4 main(in VSInput pVertexInput, out VSOutput pVertexOutput) : SV_Position {
    pVertexOutput.uv = pVertexInput.uv;
    return mul(uPerView.proj, mul(uPerView.view, float4(pVertexInput.position, 1.0)));
}
