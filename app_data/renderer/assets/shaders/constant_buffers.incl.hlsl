struct PerView
{
    float4x4 model;
    float4x4 view;
    float4x4 proj;
};

[[vk::binding(0, 1)]]
ConstantBuffer<PerView> uPerView;
