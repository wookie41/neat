#ifndef SCENE_TYPES_H
#define SCENE_TYPES_H

//---------------------------------------------------------------------------//

struct DirectionalLight
{
    float3 DirectionWS;
    float3 Color;
};

//---------------------------------------------------------------------------//

struct MeshInstancedDrawInfo
{
    uint meshInstanceIdx;
    uint materialInstanceIdx;
};

//---------------------------------------------------------------------------//

struct MeshInstanceInfo
{
    float4x4 modelMatrix;
};

//---------------------------------------------------------------------------//

#endif // SCENE_TYPES_H