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