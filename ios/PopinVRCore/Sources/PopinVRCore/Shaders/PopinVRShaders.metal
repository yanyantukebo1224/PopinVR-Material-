#include <metal_stdlib>
using namespace metal;

struct GridVertexOut {
    float4 position [[position]];
    float3 worldPosition;
};

struct GridUniforms {
    float4x4 viewProjection;
};

vertex GridVertexOut popinvr_grid_vertex(
    uint vertexID [[vertex_id]],
    const device float3 *vertices [[buffer(0)]],
    constant GridUniforms &uniforms [[buffer(1)]]
) {
    GridVertexOut out;
    float3 world = vertices[vertexID];
    out.position = uniforms.viewProjection * float4(world, 1.0);
    out.worldPosition = world;
    return out;
}

fragment float4 popinvr_grid_fragment(
    GridVertexOut in [[stage_in]],
) {
    float axisX = abs(in.worldPosition.x) < 0.015 ? 1.0 : 0.0;
    float axisZ = abs(in.worldPosition.z) < 0.015 ? 1.0 : 0.0;
    float3 base = float3(0.20, 0.24, 0.29);
    float3 color = mix(base, float3(0.15, 0.72, 0.95), axisX);
    color = mix(color, float3(0.95, 0.36, 0.20), axisZ);
    return float4(color, 1.0);
}
