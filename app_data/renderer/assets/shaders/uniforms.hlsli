struct PerView
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 InvViewProjMatrix;
    float3 CameraPositionWS;
};

struct DirectionalLight
{
    float3 DirectionWS;
    float3 Color;
};

struct PerFrame
{
    DirectionalLight Sun;
};

[[vk::binding(0, 1)]] ConstantBuffer<PerFrame> uPerFrame;

[[vk::binding(1, 1)]] ConstantBuffer<PerView> uPerView;
