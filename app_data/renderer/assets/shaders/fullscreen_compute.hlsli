[[vk::binding(0, 0)]]
cbuffer FullScreenParams : register(b0, space0) {
  float4 uInputSize;
}

struct FullScreenComputeInput
{
  uint2 cellCoord;
  float2 cellCenter;
  float2 uv;
};

FullScreenComputeInput CreateFullScreenComputeArgs(uint2 dispatchThreadId)
{
  FullScreenComputeInput input;
  input.cellCoord = dispatchThreadId.xy;
  input.cellCenter = float2(input.cellCoord) + 0.5;
  input.uv = input.cellCenter.xy * uInputSize.xy;

  return input;
}