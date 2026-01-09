[[vk::binding(0, 0)]]
cbuffer FullScreenParams : register(b0, space0) 
{
    float2 uInputTextureTexelSize;
    int2 uInputTextureDimensions;
}

struct FSInput
{
  float4 pos : SV_Position;
  float2 uv  : UV0;
};