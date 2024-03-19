struct FragmentInput
{
    [[vk::location(0)]] float3 positionWS: POSITION_WS;
    [[vk::location(1)]] float2 uv : TEXCOORD0;
    [[vk::location(2)]] uint materialInstanceIdx : MATERIAL_INSTANCE_IDX;
    [[vk::location(3)]] float3 normal : NORMAL;
    [[vk::location(4)]] float3 binormal : BINORMAL;
    [[vk::location(5)]] float3 tangent : TANGENT;
};
