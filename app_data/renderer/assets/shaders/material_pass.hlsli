#ifndef MATERIAL_PASS_H
#define MATERIAL_PASS_H

#include "scene_types.hlsli"

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
StructuredBuffer<MeshInstancedDrawInfo> gMeshInstancedDrawInfoBuffer : register(t0, space2);

//---------------------------------------------------------------------------//

#endif // MATERIAL_PASS_H