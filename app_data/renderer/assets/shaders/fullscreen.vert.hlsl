
#include "fullscreen.hlsli"

FragmentInput main(uint pVertexId : SV_VertexID)
{
  uint vertexId = 2 - pVertexId;

  FragmentInput output;

  output.pos = float4(
    float(vertexId / 2) * 4.0 - 1.0,
    float(vertexId % 2) * 4.0 - 1.0, 
    0.0, 1.0);

  output.uv = float2(
    float(vertexId / 2) * 2.0, 
    1 - float(vertexId % 2) * 2.0);

  return output;
}