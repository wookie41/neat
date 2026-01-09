//---------------------------------------------------------------------------//

#include "resources.hlsli"
#include "fullscreen.hlsli"
#include "common.hlsli"
#include "math.hlsli"

//---------------------------------------------------------------------------//

[[vk::binding(1, 0)]]
Texture2D<float> depthBufferTex : register(t0, space0);

[[vk::binding(2, 0)]]
Texture2D<float2> motionVectorsTex : register(t1, space0);

[[vk::binding(3, 0)]]
Texture2D<float3> currentHDRTex : register(t2, space0);

[[vk::binding(4, 0)]]
Texture2D<float3> historyHDRTex : register(t3, space0);

//---------------------------------------------------------------------------//

float3 PSMain(in FSInput pFragmentInput) : SV_Target0
{
    const uint2 currentTexCoords = floor(pFragmentInput.uv * float2(uInputTextureDimensions));

    if ((uRenderSettings.TAA.Flags & TAA_FLAG_ENABLED) == 0)
        return currentHDRTex[currentTexCoords];

    if ((uRenderSettings.TAA.Flags & TAA_FLAG_RESET) > 0)
        return currentHDRTex[currentTexCoords];

    // Sample motion vector
    uint2 depthDilatedCoords = currentTexCoords;
    if ((uRenderSettings.TAA.Flags & TAA_FLAG_DILATE_MOTION_VECTORS) > 0)
    {
        float closestDepth = 0;
        uint2 closestDepthCoords;

        for (int y = -1; y <= 1; ++y)
        {
            for (int x = -1; x <= 1; ++x)
            {
                const uint2 coords = currentTexCoords + int2(x, y);
                const float depth = depthBufferTex[coords];

                if (depth > closestDepth)
                {
                    closestDepth = depth;
                    closestDepthCoords = coords;
                }
            }
        }

        depthDilatedCoords = closestDepthCoords;
    }

    const float2 motionVector = motionVectorsTex[depthDilatedCoords];
    const float2 historyUV = pFragmentInput.uv + motionVector;
    
    // Reject history sample if offscreen
    // TODO: Spatial filter 
    if (IsUVOutOfRange(historyUV))
        return currentHDRTex[currentTexCoords];

    // Sample history
    float3 historyColor = float3(0.xxx);
    if ((uRenderSettings.TAA.Flags & TAA_FLAG_HISTORY_SINGLE_TAP) > 0)
        historyColor = historyHDRTex.SampleLevel(uLinearClampToEdgeSampler, historyUV, 0);
    else
        historyColor = BicubicSample5Tap(historyHDRTex, uLinearClampToEdgeSampler, historyUV * uInputTextureDimensions, uInputTextureTexelSize);

    // Resolve current color, prepare neighbourood and moments for color cliping
    float3 currentSampleTotal = float3(0.xxx);
    float currentSampleWeight = 0.0f;
    // Min and Max used for history clipping
    float3 neighborhoodMin = float3(FLT_MAX.xxx);
    float3 neighborhoodMax = float3(FLT_MIN.xxx);
    // Cache of moments used in the resolve phase
    float3 m1 = float3(0.xxx);
    float3 m2 = float3(0.xxx);

    for (int x = -1; x <= 1; ++x)
    {
        for (int y = -1; y <= 1; ++y)
        {
            const int2 pixelPosition = clamp(currentTexCoords + int2(x, y), int2(0.xx), uInputTextureDimensions.x - 1);
            const float3 currentSample = currentHDRTex[pixelPosition];
            const float2 subsamplePosition = float2(x, y);
            const float subsampleDistance = length(subsamplePosition);
            const float subsampleWeight = FilterBlackmanHarris(subsampleDistance);

            currentSampleTotal += currentSample * subsampleWeight;
            currentSampleWeight += subsampleWeight;

            neighborhoodMin = min(neighborhoodMin, currentSample);
            neighborhoodMax = max(neighborhoodMax, currentSample);

            m1 += currentSample;
            m2 += currentSample * currentSample;
        }
    }

    // Calculate current sample color
    const float3 currentColor = currentSampleTotal / currentSampleWeight;

    if (isnan(historyColor.x) || isnan(historyColor.y) || isnan(historyColor.z))
        return currentColor;

    // Constrain history (color clip)
    const float rcpSampleCount = 1.0f / 9.0f;
    const float gamma = 1.0f;
    const float3 mu = m1 * rcpSampleCount;
    const float3 sigma = sqrt(abs((m2 * rcpSampleCount) - (mu * mu)));
    const float3 minc = mu - gamma * sigma;
    const float3 maxc = mu + gamma * sigma;

    historyColor.rgb = ClipAABB(minc, maxc, float4(historyColor, 1), 1.0f).rgb;

    // Resolve: combine history and current colors for final pixel color.
    float3 currentWeight = float3(0.1f.xxx);
    float3 historyWeight = float3(1.0 - currentWeight);

    // Temporal filtering
    if ((uRenderSettings.TAA.Flags & TAA_FLAG_TEMPORAL_FILTER) > 0)
    {
        const float3 temporalWeight = clamp(abs(neighborhoodMax - neighborhoodMin) / currentColor, float3(0.xxx), float3(1.xxx));
        historyWeight = clamp(lerp(float3(0.25.xxx), float3(0.85.xxx), temporalWeight), float3(0.xxx), float3(1.xxx));
        currentWeight = 1.0f - historyWeight;
    }

    // Inverse luminance filtering
    if ((uRenderSettings.TAA.Flags & TAA_FLAG_INVERSE_LUMINANCE_FILTERING) > 0 ||
        (uRenderSettings.TAA.Flags & TAA_FLAG_LUMINANCE_DIFFERENCE_FILTERING) > 0)

    {
        // Calculate compressed colors and luminances
        const float3 compressed_source = currentColor / (max(max(currentColor.r, currentColor.g), currentColor.b) + 1.0f);
        const float3 compressed_history = historyColor / (max(max(historyColor.r, historyColor.g), historyColor.b) + 1.0f);
        const float luminanceSource = RGBToLuminance(compressed_source);
        const float luminanceHistory = RGBToLuminance(compressed_history);

        if ((uRenderSettings.TAA.Flags & TAA_FLAG_LUMINANCE_DIFFERENCE_FILTERING) > 0)
        {
            const float unbiasedDiff = abs(luminanceSource - luminanceHistory) / max(luminanceSource, max(luminanceHistory, 0.2));
            const float unbiasedWeight = 1.0 - unbiasedDiff;
            const float unbiasedWeightSqr = unbiasedWeight * unbiasedWeight;
            const float kFeedback = lerp(0.0f, 1.0f, unbiasedWeightSqr);

            historyWeight = float3(1.0 - kFeedback.xxx);
            currentWeight = float3(kFeedback.xxx);
        }

        currentWeight *= 1.0 / (1.0 + luminanceSource);
        historyWeight *= 1.0 / (1.0 + luminanceHistory);
    }

    return (currentColor * currentWeight + historyColor * historyWeight) / max(currentWeight + historyWeight, 0.00001);
}

//---------------------------------------------------------------------------//