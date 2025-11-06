//---------------------------------------------------------------------------//

float3 interpolation_c2( float3 x ) { return x * x * x * (x * (x * 6.0 - 15.0) + 10.0); }

//---------------------------------------------------------------------------//

// from: https://github.com/BrianSharpe/GPU-Noise-Lib/blob/master/gpu_noise_lib.glsl
void perlin_hash(float3 gridcell, float s, bool tile, 
                    out float4 lowz_hash_0,
                    out float4 lowz_hash_1,
                    out float4 lowz_hash_2,
                    out float4 highz_hash_0,
                    out float4 highz_hash_1,
                    out float4 highz_hash_2)
{
    const float2 OFFSET = float2( 50.0, 161.0 );
    const float DOMAIN = 69.0;
    const float3 SOMELARGEFLOATS = float3( 635.298681, 682.357502, 668.926525 );
    const float3 ZINC = float3( 48.500388, 65.294118, 63.934599 );

    gridcell.xyz = gridcell.xyz - floor(gridcell.xyz * ( 1.0 / DOMAIN )) * DOMAIN;
    float d = DOMAIN - 1.5;
    float3 gridcell_inc1 = step( gridcell, float3( d,d,d ) ) * ( gridcell + 1.0 );

    gridcell_inc1 = tile ? gridcell_inc1 % s : gridcell_inc1;

    float4 P = float4( gridcell.xy, gridcell_inc1.xy ) + OFFSET.xyxy;
    P *= P;
    P = P.xzxz * P.yyww;
    float3 lowz_mod = float3( 1.0 / ( SOMELARGEFLOATS.xyz + gridcell.zzz * ZINC.xyz ) );
    float3 highz_mod = float3( 1.0 / ( SOMELARGEFLOATS.xyz + gridcell_inc1.zzz * ZINC.xyz ) );
    lowz_hash_0 = frac(P * lowz_mod.xxxx);
    highz_hash_0 = frac(P * highz_mod.xxxx);
    lowz_hash_1 = frac(P * lowz_mod.yyyy);
    highz_hash_1 = frac( P * highz_mod.yyyy );
    lowz_hash_2 = frac( P * lowz_mod.zzzz );
    highz_hash_2 = frac( P * highz_mod.zzzz );
}

//---------------------------------------------------------------------------//

// from: https://github.com/BrianSharpe/GPU-Noise-Lib/blob/master/gpu_noise_lib.glsl
float perlin(float3 P, float s, bool tile) {
    P *= s;

    float3 Pi = floor(P);
    float3 Pi2 = floor(P);
    float3 Pf = P - Pi;
    float3 Pf_min1 = Pf - 1.0;

    float4 hashx0, hashy0, hashz0, hashx1, hashy1, hashz1;
    perlin_hash( Pi2, s, tile, hashx0, hashy0, hashz0, hashx1, hashy1, hashz1 );

    float4 grad_x0 = hashx0 - 0.49999;
    float4 grad_y0 = hashy0 - 0.49999;
    float4 grad_z0 = hashz0 - 0.49999;
    float4 grad_x1 = hashx1 - 0.49999;
    float4 grad_y1 = hashy1 - 0.49999;
    float4 grad_z1 = hashz1 - 0.49999;
    float4 grad_results_0 = 1.0 / sqrt( grad_x0 * grad_x0 + grad_y0 * grad_y0 + grad_z0 * grad_z0 ) * ( float2( Pf.x, Pf_min1.x ).xyxy * grad_x0 + float2( Pf.y, Pf_min1.y ).xxyy * grad_y0 + Pf.zzzz * grad_z0 );
    float4 grad_results_1 = 1.0 / sqrt( grad_x1 * grad_x1 + grad_y1 * grad_y1 + grad_z1 * grad_z1 ) * ( float2( Pf.x, Pf_min1.x ).xyxy * grad_x1 + float2( Pf.y, Pf_min1.y ).xxyy * grad_y1 + Pf_min1.zzzz * grad_z1 );

    float3 blend = interpolation_c2( Pf );
    float4 res0 = lerp( grad_results_0, grad_results_1, blend.z );
    float4 blend2 = float4( blend.xy, float2( 1.0 - blend.xy ) );
    float final = dot( res0, blend2.zxzx * blend2.wwyy );
    final *= 1.0/sqrt(0.75);
    return ((final * 1.5) + 1.0) * 0.5;
}

//---------------------------------------------------------------------------//

float perlin(float3 P) {
    return perlin(P, 1, false);
}

//---------------------------------------------------------------------------//

float get_perlin_7_octaves(float3 p, float s) {
    float3 xyz = p;
    float f = 1.0;
    float a = 1.0;

    float perlin_value = 0.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r; a *= 0.5; f *= 2.0;
    perlin_value += a * perlin(xyz, s * f, true).r;

    return perlin_value;
}

//---------------------------------------------------------------------------//

[[vk::binding(0, 0)]]
RWTexture3D<float> OutputNoiseTex : register(u0, space0);

//---------------------------------------------------------------------------//

[numthreads(8, 8, 1)]
void CSMain(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    int3 pos = int3(dispatchThreadId.xyz);

    float3 xyz = pos / 64.0;

    float perlin_data = get_perlin_7_octaves(xyz, 8.0);

    OutputNoiseTex[pos] = perlin_data;
}

//---------------------------------------------------------------------------//