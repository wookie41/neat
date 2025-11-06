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

// Projects depth buffer (1 .. 0) value back to view space (near .. inf)
float LinearizeDepth(in float hwDepth, in float near)
{
    return (near / hwDepth);
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

    pFrustumPoints[0] = (farPlaneCenter + pUp * heightFar + right * widthFar);
    pFrustumPoints[1] = (farPlaneCenter + pUp * heightFar - right * widthFar);
    pFrustumPoints[2] = (farPlaneCenter - pUp * heightFar + right * widthFar);
    pFrustumPoints[3] = (farPlaneCenter - pUp * heightFar - right * widthFar);

    pFrustumPoints[4] = (nearPlaneCenter + pUp * heightNear + right * widthNear);
    pFrustumPoints[5] = (nearPlaneCenter + pUp * heightNear - right * widthNear);
    pFrustumPoints[6] = (nearPlaneCenter - pUp * heightNear + right * widthNear);
    pFrustumPoints[7] = (nearPlaneCenter - pUp * heightNear - right * widthNear);

    frustumCenter = 0;

    [unroll]
    for (int i = 0; i < 8; i++)
        frustumCenter += pFrustumPoints[i];

    frustumCenter /= 8.f;
}

//---------------------------------------------------------------------------//

float4x4 CreateOrthographicMatrix(float left, float right, float bottom, float top, float near, float far)
{
    float4x4 matrix;

    // Initialize to zero
    matrix = (float4x4)0;

    // Calculate the width, height and depth of the view volume
    float width = right - left;
    float height = top - bottom;
    float depth = far - near;

    // Fill the matrix elements
    // For right-handed system:
    // - x axis points right (positive X increases to the right)
    // - y axis points up (positive Y increases upward)
    // - z axis points out of the screen (positive Z increases toward viewer)

    matrix._11 = 2.0f / width;  // 2/(r-l)
    matrix._22 = 2.0f / height; // 2/(t-b)
    matrix._33 = 1.0f / depth;  // 1/(f-n) for right-handed
    matrix._44 = 1.0f;

    // Translation terms
    matrix._41 = -(right + left) / width;  // -(r+l)/(r-l)
    matrix._42 = -(top + bottom) / height; // -(t+b)/(t-b)
    matrix._43 = -near / depth;            // -n/(f-n) for right-handed

    return matrix;
}
//---------------------------------------------------------------------------//

float SliceToExponentialDepthJittered(in float near, in float far, in float jitter, in int slice, in int numSlices)
{
    return near * pow(far / near, (float(slice) + 0.5f + jitter) / float(numSlices));
}
//---------------------------------------------------------------------------//

// http://www.aortiz.me/2018/12/21/CG.html
// Convert linear depth (near...far) to (0...1) value distributed with exponential functions
// like SliceToExponentialDepthJittered.
// This function is performing all calculations, a more optimized one precalculates factors on CPU.
float LinearDepthToUV(in float near, in float far, in float linearDepth, in int numSlices) {
    const float oneOverLogFOverN = 1.0f / log2(far / near);
    const float scale = numSlices * oneOverLogFOverN;
    const float bias = -(numSlices * log2(near) * oneOverLogFOverN);
    return max(log2(linearDepth) * scale + bias, 0.0f) / float(numSlices);
}

//---------------------------------------------------------------------------//

// Convert linear depth (near...far) to raw depth (0..1)
float LinearDepthToRawDepth(in float linearDepth, in float near, in float far)
{
    return (near * far) / (linearDepth * (near - far)) - far / (near - far);
}

//---------------------------------------------------------------------------//

// Convert linear depth (near...far) to raw depth (0..1)
float LinearDepthToRawDepth2(in float linearDepth, in float near, in float far)
{
    return (near * far) / (linearDepth * (far - near)) - near / (far - near);
}

//---------------------------------------------------------------------------//

// Convert raw depth (0..1) to linear (near...far)
float RawDepthToLinearDepth(in float rawDepth, in float near, in float far)
{
    return near * far / (far + rawDepth * (near - far));
}


//---------------------------------------------------------------------------//

#endif // MATH_H