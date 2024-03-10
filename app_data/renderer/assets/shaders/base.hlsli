struct FragmentInput {
    [[vk::location(0)]] float2 uv                   : TEXCOORD0;
    [[vk::location(1)]] uint materialInstanceIdx    : MATERIAL_INSTANCE_IDX;
};
