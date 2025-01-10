#ifndef GEOMETRY_PASS_INSTANCED_MESH_H
#define GEOMETRY_PASS_INSTANCED_MESH_H

#include "scene_types.hlsli"

#ifndef INSTANCED_MESH_PASS_CUSTOM_DATA_TYPE

struct InstancedMeshDummyData
{
    uint data;
};

#define INSTANCED_MESH_PASS_CUSTOM_DATA_TYPE InstancedMeshDummyData

#endif

// Custom uniform data that the user of the instanced mesh task can use to pass additional data
// INSTANCED_MESH_PASS_CUSTOM_DATA_TYPE has to be defined befire instanced_mesh.hlsli is included
[[vk::binding(0, 0)]] ConstantBuffer<INSTANCED_MESH_PASS_CUSTOM_DATA_TYPE> uPassCustomData : register(b0, space0);

[[vk::binding(1, 0)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer : register(t0, space0);

MeshInstancedDrawInfo FetchMeshInstanceInfo(in uint pInstanceId)
{
    return gMeshInstancedDrawInfoBuffer[pInstanceId];
}

#endif // GEOMETRY_PASS_INSTANCED_MESH_H
