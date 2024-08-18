#ifndef PACKING_H
#define PACKING_H

// Octahedron normal vector encoding (http://jcgt.org/published/0003/02/01/)
float2 signNotZero(float2 v)
{
  return float2((v.x >= 0.0) ? 1.0 : -1.0, 
                 (v.y >= 0.0) ? 1.0 : -1.0);
}

float2 encodeNormal(in float3 v)
{
  float2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));
  return (v.z <= 0.0) ? ((1.0 - abs(p.yx)) * signNotZero(p)) : p;
}

float3 decodeNormal(in float2 e)
{
  float3 v = float3(e.xy, 1.0 - abs(e.x) - abs(e.y));

  if (v.z < 0) 
    v.xy = (1.0 - abs(v.yx)) * signNotZero(v.xy);

  return normalize(v);
}

float3 decodeNormalMap(in float4 normalSample)
{
  float3 normal;
  normal.xy = (normalSample.rg);
  normal.z = sqrt(1.0 - ((normal.x * normal.x) - (normal.y * normal.y)));
  return normal.xyz;
}

#endif // PACKING_H