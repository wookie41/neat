#ifndef MATH_H
#define MATH_H

//---------------------------------------------------------------------------//

#define MATH_PI_RCP 0.31830988618f
#define MATH_PI 3.1415926535f

#define FLT_MAX 3.402823466e+38f
#define FLT_MIN 1.175494351e-38f

//---------------------------------------------------------------------------//

float3 UnprojectDepthToWorldPos(in float2 uv, in float depth, in float4x4 invViewProjMatrix)
{
    // UV grows downwards, so flip for clip space Y
    uv.y = 1 - uv.y;

    const float4 unprojPos = mul(invViewProjMatrix, float4(uv.xy * 2.0 - 1.0, depth, 1.0));
    return unprojPos.xyz / unprojPos.www;
}

//---------------------------------------------------------------------------//

// Projects depth buffer value back to view space
float LinearizeDepth(float hwDepth, float near)
{
    return -near / hwDepth;
}

//---------------------------------------------------------------------------//

void ComputeFrustumPoints(
    float pNear, float pFar, float pAspectRatio, float pTanFovHalf,
    float3 pPosition, float3 pForward, float3 pUp,
    out float3 pFrustumPoints[8], out float3 frustumCenter)
{
    const float3 right = normalize(cross(pForward, pUp));

    const float3 nearPlaneCenter = pPosition.xyz + pForward.xyz * pNear;
    const float3 farPlaneCenter = pPosition.xyz + pForward.xyz * pFar;

    const float heightNear = pTanFovHalf * pNear;
    const float heightFar = pTanFovHalf * pFar;

    const float widthNear = heightNear * pAspectRatio;
    const float widthFar = heightFar * pAspectRatio;

    pFrustumPoints[0] = farPlaneCenter + pUp * heightFar + right * widthFar;
    pFrustumPoints[1] = farPlaneCenter + pUp * heightFar - right * widthFar;
    pFrustumPoints[2] = farPlaneCenter - pUp * heightFar + right * widthFar;
    pFrustumPoints[3] = farPlaneCenter - pUp * heightFar - right * widthFar;

    pFrustumPoints[4] = nearPlaneCenter + pUp * heightNear + right * widthNear;
    pFrustumPoints[5] = nearPlaneCenter + pUp * heightNear - right * widthNear;
    pFrustumPoints[6] = nearPlaneCenter - pUp * heightNear + right * widthNear;
    pFrustumPoints[7] = nearPlaneCenter - pUp * heightNear - right * widthNear;

    frustumCenter = float3(0.xxx);
    for (int i = 0; i < 8; i++)
    {
        frustumCenter += pFrustumPoints[i];
    }

    frustumCenter /= 8.f;
}

//---------------------------------------------------------------------------//

#endif // MATH_H