#define MATH_PI_RCP 0.31830988618

float3 UnprojectDepthToWorldPos(in float2 uv, in float depth, in float4x4 invViewProjMatrix)
{
    float4 unprojPos = mul(invViewProjMatrix, float4(uv.xy * 2.0 - 1.0, depth, 1.0));
    return unprojPos.xyz / unprojPos.www;
}
