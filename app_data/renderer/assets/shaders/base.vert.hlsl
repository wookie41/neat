struct VSInput {
    [[vk::location(0)]] float3 position  : POSITION; 
    [[vk::location(1)]] float3 color     : COLOR;
    [[vk::location(2)]] float2 uv        : TEXCOORD0;
};

struct VSOutput {
    [[vk::location(0)]] float3 fragColor : FRAGCOLOR;
    [[vk::location(1)]] float2 uv        : TEXCOORD0;
};

struct PerView
{
    float4x4 model;
    float4x4 view;
    float4x4 proj;
};

[[vk::binding(0, 0)]]
ConstantBuffer<PerView> gPerView;

float4 main(in VSInput pVertexInput, out VSOutput pVertexOutput) : SV_Position {
    pVertexOutput.fragColor = pVertexInput.color;
    pVertexOutput.uv = pVertexInput.uv;
    return mul(gPerView.proj, 
        mul(gPerView.view, 
        mul(gPerView.model, 
        float4(pVertexInput.position, 1.0))));
}
