//---------------------------------------------------------------------------//

#include "common.hlsli"
#include "resources.hlsli"
#include "noise.hlsli"
#include "math.hlsli"
#include "shadow_sampling.hlsli"
#include "volumetric_fog.hlsli"

//---------------------------------------------------------------------------//

#define FROXEL_DISPATCH_SIZE_X 8
#define FROXEL_DISPATCH_SIZE_Y 8
#define FROXEL_DISPATCH_SIZE_Z 1

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
cbuffer VolumetricFogParams : register(b0, space0)
{
    uint3 froxelDimensions;
    float temporalReprojectionJitterScale;

    int noiseType;
    float noiseScale;
    int spatialFilterEnabled;
    int temporalFilterEnabled;

    float heightFogFalloff;
    float scatteringFactor;
    float volumetricNoisePositionMultiplier;
    float volumetricNoiseSpeedMultiplier;

    float constantFogDensity;
    float3 constantFogColor;

    float heightFogDensity;
    float3 heightFogColor;

    float boxFogDensity;
    float3 boxFogPosition;

    float3 boxFogSize;
    uint _padding1;

    float3 boxFogColor;
    uint _padding2;

    float phaseAnisotrophy01;
    int phaseFunctionType;
    int volumetricFogOpacityAAEnabled;
    float temporalReprojectionPercentage;

    float3 volumetricNoiseDirection;
    int _padding3;

    float4x4 ViewProjectionMatrix;
    float4x4 InvViewProjMatrix;
    float4x4 PreviousViewProjectionMatrix;
}

[[vk::binding(1, 0)]]
Texture2D<float2> BlueNoiseTexture : register(t0, space0);

[[vk::binding(2, 0)]]
Texture3D<float> VolumetricNoiseTexture : register(t1, space0);

//---------------------------------------------------------------------------//

float GenerateNoise(in float2 pixel, in int frame, in float scale)
{
    // Animated blue noise using golden ratio.
    if (noiseType == 0)
    {
        // Sample blue noise
        const float2 uv = float2(pixel.xy / froxelDimensions.xy);
        const float2 blueNoise = BlueNoiseTexture.SampleLevel(uLinearRepeatSampler, uv, 0).rg;

        const float kGoldenRatioConjugate = 0.61803398875;
        const float blueNoise0 = frac(ToLinear1(blueNoise.r) + float(uPerFrame.FrameIdMod64) * kGoldenRatioConjugate);
        const float blueNoise1 = frac(ToLinear1(blueNoise.g) + float(uPerFrame.FrameIdMod64) * kGoldenRatioConjugate);

        return TriangularNoise(blueNoise0, blueNoise1) * scale;
    }

    // Interleaved gradient noise
    if (noiseType == 1)
    {
        float noise0 = InterleavedGradientNoise(pixel, frame);
        float noise1 = InterleavedGradientNoise(pixel, frame + 1);

        return TriangularNoise(noise0, noise1) * scale;
    }

    // Initial noise attempt, left for reference.
    return (InterleavedGradientNoise(pixel, frame) * scale) - (scale * 0.5f);
}

//---------------------------------------------------------------------------//

float3 FroxelCoordToWorldPosition(in int3 froxelCoord)
{
    const float2 uv = (float2(froxelCoord.xy) + float2(0.5.xx) + float2(uPerFrame.HaltonX, uPerFrame.HaltonY) * temporalReprojectionJitterScale) / float2(froxelDimensions.xy);
    const float depthJitter = GenerateNoise(float2(froxelCoord.xy), uPerFrame.FrameId, noiseScale);
    const float linearDepth = SliceToExponentialDepthJittered(uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar, depthJitter, froxelCoord.z, froxelDimensions.z);
    const float rawDepth = LinearDepthToRawDepth(linearDepth, uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar);
    return UnprojectDepthToWorldPos(uv, rawDepth, InvViewProjMatrix);
}

//---------------------------------------------------------------------------//

float3 FroxelCoordToWorldPositionCameraSpace(in int3 froxelCoord)
{
    const float2 uv = (float2(froxelCoord.xy) + float2(0.5.xx) + float2(uPerFrame.HaltonX, uPerFrame.HaltonY) * temporalReprojectionJitterScale) / float2(froxelDimensions.xy);
    const float depthJitter = GenerateNoise(float2(froxelCoord.xy), uPerFrame.FrameId, noiseScale);
    const float linearDepth = SliceToExponentialDepthJittered(uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar, depthJitter, froxelCoord.z, froxelDimensions.z);
    const float rawDepth = uPerView.CurrentView.CameraNearPlane / linearDepth;
    return UnprojectDepthToWorldPos(uv, rawDepth, uPerView.CurrentView.InvViewProjMatrix);
}

//---------------------------------------------------------------------------//

float4 ScatteringExtinctionFromColorDensity(float3 color, float density)
{
    const float extinction = scatteringFactor * density;
    return float4(color * extinction, extinction);
}

//---------------------------------------------------------------------------//

// Equations from http://patapom.com/topics/Revision2013/Revision%202013%20-%20Real-time%20Volumetric%20Rendering%20Course%20Notes.pdf
float HenyeyGreenstein(in float g, in float costh)
{
    const float numerator = 1.0 - g * g;
    const float denominator = 4.0 * MATH_PI * pow(1.0 + g * g - 2.0 * g * costh, 3.0 / 2.0);
    return numerator / denominator;
}

//---------------------------------------------------------------------------//

float Shlick(float g, float costh)
{
    const float numerator = 1.0 - g * g;
    const float g_costh = g * costh;
    const float denominator = 4.0 * MATH_PI * ((1 + g_costh) * (1 + g_costh));
    return numerator / denominator;
}

//---------------------------------------------------------------------------//

float CornetteShanks(in float g, in float costh)
{
    const float numerator = 3.0 * (1.0 - g * g) * (1.0 + costh * costh);
    const float denominator = 4.0 * MATH_PI * 2.0 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * costh, 3.0 / 2.0);
    return numerator / denominator;
}

//---------------------------------------------------------------------------//

// As found in "Real-time Rendering of Dynamic Clouds" by Xiao-Lei Fan, Li-Min Zhang, Bing-Qiang Zhang, Yuan Zhang [2014]
float CornetteShanksApproximated(in float g, in float costh)
{
    const float numerator = 3.0 * (1.0 - g * g) * (1.0 + costh * costh);
    const float denominator = 4.0 * MATH_PI * 2.0 * (2.0 + g * g) * (1.0 + g * g - 2.0 * g * costh);
    return (numerator / denominator) + (g * costh);
}
//---------------------------------------------------------------------------//

float PhaseFunction(in float3 V, in float3 L, in float g)
{
    const float cosTheta = dot(V, L);

    if (phaseFunctionType == 0)
        return HenyeyGreenstein(g, cosTheta);

    if (phaseFunctionType == 1)
        return CornetteShanks(g, cosTheta);

    if (phaseFunctionType == 2)
        return Shlick(g, cosTheta);

    return CornetteShanksApproximated(g, cosTheta);
}
//---------------------------------------------------------------------------//

#if defined(INJECT_DATA_SHADER)

//---------------------------------------------------------------------------//

[[vk::binding(3, 0)]]
RWTexture3D<float4> ScatteringExtinctionTexture : register(u0, space0);

//---------------------------------------------------------------------------//

[numthreads(FROXEL_DISPATCH_SIZE_X, FROXEL_DISPATCH_SIZE_Y, FROXEL_DISPATCH_SIZE_Z)]
void InjectData(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const int3 froxelCoord = int3(dispatchThreadId);
    const float3 worldPosition = FroxelCoordToWorldPosition(froxelCoord);

    float4 scatteringAndExtinction = float4(0.xxxx);

    const float3 volumetricNoiseUV = 
        worldPosition * volumetricNoisePositionMultiplier + 
        normalize(volumetricNoiseDirection) * float(uPerFrame.FrameId) * volumetricNoiseSpeedMultiplier;

    float volumetricNoise = VolumetricNoiseTexture.SampleLevel(uLinearRepeatSampler, volumetricNoiseUV, 0).r;
    volumetricNoise = saturate(volumetricNoise * volumetricNoise);

    // Add constant fog
    scatteringAndExtinction += ScatteringExtinctionFromColorDensity(constantFogColor, constantFogDensity * volumetricNoise);

    // Add height fog
    scatteringAndExtinction += ScatteringExtinctionFromColorDensity(heightFogColor, heightFogDensity * exp(-heightFogFalloff * max(worldPosition.y, 0)) * volumetricNoise);

    // Add box fog
    const float3 boxFog = abs(worldPosition - boxFogPosition);
    if (all(boxFog <= boxFogSize))
        scatteringAndExtinction += ScatteringExtinctionFromColorDensity(boxFogColor, boxFogDensity * volumetricNoise);

    ScatteringExtinctionTexture[froxelCoord] = scatteringAndExtinction;
}

#endif

//---------------------------------------------------------------------------//

#if defined(SCATTER_LIGHT_SHADER)

[[vk::binding(3, 0)]]
Texture2D<float> CascadeShadowTextures[] : register(t2, space0);

[[vk::binding(4, 0)]]
StructuredBuffer<ShadowCascade> ShadowCascades : register(t3, space0);

[[vk::binding(5, 0)]]
StructuredBuffer<ExposureInfo> ExposureBuffer : register(t4, space0);

[[vk::binding(6, 0)]]
RWTexture3D<float4> LightScatteringTexture : register(u0, space0);

//---------------------------------------------------------------------------//

[numthreads(FROXEL_DISPATCH_SIZE_X, FROXEL_DISPATCH_SIZE_Y, FROXEL_DISPATCH_SIZE_Z)]
void ScatterLight(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const int3 froxelCoord = int3(dispatchThreadId);
    const float3 worldPosition = FroxelCoordToWorldPositionCameraSpace(froxelCoord);
    const float3 viewPostion = mul(uPerView.CurrentView.ViewMatrix, float4(worldPosition, 1)).xyz;
    const float3 V = normalize(uPerView.CurrentView.CameraPositionWS - worldPosition);

    int cascadeIndex;
    const float dirLightShadow = SampleDirectionalLightShadowSingleTap(CascadeShadowTextures, ShadowCascades, worldPosition, viewPostion, cascadeIndex);

    const float3 ambientTerm = 0.02;
    const float sunStrengthExposed = uPerFrame.Sun.Strength * ExposureBuffer[0].Exposure;
    const float3 lightScattering = uPerFrame.Sun.Color * sunStrengthExposed * PhaseFunction(V, -uPerFrame.Sun.DirectionWS, phaseAnisotrophy01) * dirLightShadow + ambientTerm;

    LightScatteringTexture[froxelCoord] = float4(lightScattering, 0);
}

#endif

//---------------------------------------------------------------------------//

#if defined(INTEGRATE_LIGHT_SHADER)

[[vk::binding(3, 0)]]
Texture3D<float4> ScatteringExtinctionTexture : register(t2, space0);

[[vk::binding(4, 0)]]
Texture3D<float4> LightScatteringTexture : register(t3, space0);

[[vk::binding(5, 0)]]
RWTexture3D<float4> IntegratedLightScatteringTexture : register(u0, space0);

//---------------------------------------------------------------------------//

[numthreads(FROXEL_DISPATCH_SIZE_X, FROXEL_DISPATCH_SIZE_Y, 1)]
void IntegrateLight(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    int3 froxelCoord = int3(dispatchThreadId);
    const float3 froxelDimensionsRcp = 1.f / float3(froxelDimensions.xyz);

    float3 integratedScattering = float3(0.xxx);
    float integratedTransmittance = 1;

    float currentZ = uPerFrame.VolumetricFogNear;

    for (int z = 0; z < froxelDimensions.z; ++z)
    {
        froxelCoord.z = z;

        const float nextZ = SliceToExponentialDepthJittered(uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar, 0, z + 1, froxelDimensions.z);

        const float zStep = abs(nextZ - currentZ);
        currentZ = nextZ;

        const float3 froxelUVW = float3(froxelCoord) * froxelDimensionsRcp;

        const float4 sampledScatteringExtinction = ScatteringExtinctionTexture.Sample(uLinearClampToEdgeSampler, froxelUVW);
        const float3 scatteredLight = LightScatteringTexture.Sample(uLinearClampToEdgeSampler, froxelUVW).rgb;
        const float3 scattering = sampledScatteringExtinction.rgb * scatteredLight;

        if (sampledScatteringExtinction.w > 0)
        {
            const float clampedExtinction = max(sampledScatteringExtinction.w, EPS_9);
            const float transmittance = exp(-sampledScatteringExtinction.w * zStep);

            const float3 currentCellScattering = (scattering.rgb - (scattering.rgb * transmittance)) / clampedExtinction;

            integratedScattering += (currentCellScattering);
            integratedTransmittance *= transmittance;
        }
        
        float3 storedScattering = integratedScattering;

        if (volumetricFogOpacityAAEnabled > 0)
        {
            const float opacity = max(1 - integratedTransmittance, EPS_9);
            storedScattering /= opacity;
        }

        IntegratedLightScatteringTexture[froxelCoord] = float4(storedScattering, integratedTransmittance);
    }
}

//---------------------------------------------------------------------------//

#endif

//---------------------------------------------------------------------------//

#if defined(SPATIAL_FILTER_SHADER)

#define SIGMA_FILTER 4.0
#define RADIUS 2

float gaussian(in float radius, in float sigma)
{
    const float v = radius / sigma;
    return exp(-(v * v));
}

[[vk::binding(3, 0)]]
Texture3D<float4> IntegratedLightScatteringTexture : register(t2, space0);

[[vk::binding(4, 0)]]
RWTexture3D<float4> FilteredIntegratedLightScatteringTexture : register(u0, space0);

[numthreads(FROXEL_DISPATCH_SIZE_X, FROXEL_DISPATCH_SIZE_Y, FROXEL_DISPATCH_SIZE_Z)]
void SpatialFilter(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const int3 froxelCoords = int3(dispatchThreadId);
    const float3 froxelDimensionsRcp = 1.f / float3(froxelDimensions);

    float accumulatedWeight = 0;
    float4 accumulatedScatteringTransmittance = 0;

    if (spatialFilterEnabled > 0)
    {
        for (int i = -RADIUS; i <= RADIUS; ++i)
        {
            for (int j = -RADIUS; j <= RADIUS; ++j)
            {
                const int3 sampleCoords = froxelCoords + int3(i, j, 0);
                if (all(sampleCoords >= 0) && all(sampleCoords <= froxelDimensions))
                {
                    const float3 sampleUV = float3(sampleCoords) * froxelDimensionsRcp;
                    const float weight = gaussian(length(int2(i, j)), SIGMA_FILTER);

                    const float4 scatteringTransmittance = IntegratedLightScatteringTexture.Sample(uLinearClampToEdgeSampler, sampleUV);

                    accumulatedWeight += weight;
                    accumulatedScatteringTransmittance += (scatteringTransmittance * weight);
                }
            }
        }

        FilteredIntegratedLightScatteringTexture[froxelCoords] = accumulatedScatteringTransmittance / accumulatedWeight;
    }
    else
    {
        FilteredIntegratedLightScatteringTexture[froxelCoords] = IntegratedLightScatteringTexture.Sample(uLinearClampToEdgeSampler, froxelCoords * froxelDimensionsRcp);
    }
}

#endif

#if defined(TEMPORAL_FILTER_SHADER)

[[vk::binding(3, 0)]]
Texture3D<float4> CurrentIntegratedScatteringTexture : register(t2, space0);

[[vk::binding(4, 0)]]
Texture3D<float4> PreviousIntegratedScatteringTexture : register(t3, space0);

[[vk::binding(5, 0)]]
RWTexture3D<float4> FinalIntegratedScatteringTexture : register(u0, space0);

[numthreads(FROXEL_DISPATCH_SIZE_X, FROXEL_DISPATCH_SIZE_Y, FROXEL_DISPATCH_SIZE_Z)]
void TemporalFilter(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    const int3 froxelCoords = int3(dispatchThreadId);
    const float3 froxelDimensionsRcp = 1.f / float3(froxelDimensions);

    float4 scatteringTransmittance = CurrentIntegratedScatteringTexture.Sample(uLinearClampToEdgeSampler, float3(froxelCoords) * froxelDimensionsRcp);

    if (temporalFilterEnabled > 0)
    {
        const float3 froxelWorldPosition = FroxelCoordToWorldPosition(froxelCoords);
        const float4 lastFrameFroxelScreenSpacePosition = mul(PreviousViewProjectionMatrix, float4(froxelWorldPosition, 1));
        const float3 lastFrameNDC = lastFrameFroxelScreenSpacePosition.xyz / lastFrameFroxelScreenSpacePosition.w;

        const float linearDepth = RawDepthToLinearDepth(lastFrameNDC.z, uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar);
        const float depthUV = LinearDepthToUV(uPerFrame.VolumetricFogNear, uPerFrame.VolumetricFogFar, linearDepth, froxelDimensions.z);
        const float3 historyUV = float3(lastFrameNDC.x * 0.5 + 0.5, lastFrameNDC.y * -0.5 + 0.5, depthUV);

        if (all(historyUV >= 0) && all(historyUV <= 1))
        {
            float4 previousScatteringTransmittance = PreviousIntegratedScatteringTexture.SampleLevel(uLinearClampToEdgeSampler, historyUV, 0);
            previousScatteringTransmittance = max(previousScatteringTransmittance, scatteringTransmittance);

            scatteringTransmittance.rgb = lerp(previousScatteringTransmittance.rgb, scatteringTransmittance.rgb, temporalReprojectionPercentage);
            scatteringTransmittance.a = lerp(previousScatteringTransmittance.a, scatteringTransmittance.a, temporalReprojectionPercentage);
        }
    }

    FinalIntegratedScatteringTexture[froxelCoords] = scatteringTransmittance    ;
}

#endif