#ifndef GEOMETRY_PASS_INSTANCED_MESH_H
#define GEOMETRY_PASS_INSTANCED_MESH_H

#include "scene_types.hlsli"

[[vk::binding(0, 0)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer : register(t0, space0);

MeshInstancedDrawInfo FetchMeshInstanceInfo(in uint pInstanceId)
{
    return gMeshInstancedDrawInfoBuffer[pInstanceId];
}

#endif // GEOMETRY_PASS_INSTANCED_MESH_H
