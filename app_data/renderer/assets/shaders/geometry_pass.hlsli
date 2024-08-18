#ifndef GEOMETRY_PASS_H
#define GEOMETRY_PASS_H

//---------------------------------------------------------------------------//

struct MaterialVertexInput
{
    uint materialInstanceIdx;
};

//---------------------------------------------------------------------------//

struct MaterialPixelInput
{
    uint materialInstanceIdx;
    float2 uv;
    float3 vertexNormal;
    float3 vertexTangent;
    float3 vertexBinormal;
};

//---------------------------------------------------------------------------//

struct MaterialPixelOutput
{
    float3 albedo;
    float3 normal;
    float roughness;
    float metalness;
    float occlusion;
};

//---------------------------------------------------------------------------//

struct Vertex
{
    float3 position;
    float2 uv;
    float3 normal;
    float3 binormal;
    float3 tangent;
};

//---------------------------------------------------------------------------//

#endif // GEOMETRY_PASS