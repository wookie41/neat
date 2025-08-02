#ifndef BRDF_H
#define BRDF_H

//---------------------------------------------------------------------------//

// Based on https://seblagarde.wordpress.com/wp-content/uploads/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf
// For diffuse, we also use renormalized Disney BRDF and a microfacet model with a Smith correlated visibility function and a GGX NDF for specular

// Schlick's approximation of Fresnel
float F_Schlick(in float f0, in float f90, in float u)
{
    return f0 + (f90 - f0) * pow(1.f - u, 5.f);
}

//---------------------------------------------------------------------------//

float3 F_Schlick(float3 specularColor, float VdH)
{
    const float fc = pow(abs(1.0 - VdH), 5.0);
    return saturate(50.0 * specularColor.g) * fc + specularColor * (1.0 - fc);
}

//---------------------------------------------------------------------------//

// Correlated Smith visibility
float V_SmithGGXCorrelated(float NdotL, float NdotV, float alphaG)
{
    float alphaG2 = alphaG * alphaG;

    float Lambda_GGXV = NdotL * sqrt((-NdotV * alphaG2 + NdotV) * NdotV + alphaG2);
    float Lambda_GGXL = NdotV * sqrt((-NdotL * alphaG2 + NdotL) * NdotL + alphaG2);

    return 0.5f / (Lambda_GGXV + Lambda_GGXL);
}

//---------------------------------------------------------------------------//

// GGX distribution
float D_GGX(float NdotH, float m)
{
    // Divide by PI is applied later
    float m2 = m * m;
    float f = (NdotH * m2 - NdotH) * NdotH + 1;
    return m2 / (f * f);
}

//---------------------------------------------------------------------------//

float DisneyDiffuseRenormalized(float NdotV, float NdotL, float LdotH, float linearRoughness)
{
    float energyBias = lerp(0, 0.5, linearRoughness);
    float energyFactor = lerp(1.0, 1.0 / 1.51, linearRoughness);
    float fd90 = energyBias + 2.0 * LdotH * LdotH * linearRoughness;
    float f0 = 1.0;
    float lightScatter = F_Schlick(f0, fd90, NdotL).r;
    float viewScatter = F_Schlick(f0, fd90, NdotV).r;
    return lightScatter * viewScatter * energyFactor;
}

//---------------------------------------------------------------------------//

#endif // BRDF_H