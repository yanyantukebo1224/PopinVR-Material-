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

fragment float4 popinvr_grid_fragment(GridVertexOut in [[stage_in]]) {
    float axisX = abs(in.worldPosition.x) < 0.015 ? 1.0 : 0.0;
    float axisZ = abs(in.worldPosition.z) < 0.015 ? 1.0 : 0.0;
    float3 base = float3(0.20, 0.24, 0.29);
    float3 color = mix(base, float3(0.15, 0.72, 0.95), axisX);
    color = mix(color, float3(0.95, 0.36, 0.20), axisZ);
    return float4(color, 1.0);
}

struct HandUniforms {
    float4x4 modelViewProjection;
    float4x4 modelToWorld;
    float4 color;
};

struct HandVertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
};

vertex HandVertexOut popinvr_hand_vertex(
    uint vertexID [[vertex_id]],
    const device float3 *positions [[buffer(0)]],
    const device float3 *normals [[buffer(1)]],
    constant HandUniforms &uniforms [[buffer(2)]]
) {
    HandVertexOut out;
    out.position = uniforms.modelViewProjection * float4(positions[vertexID], 1.0);
    out.normal = normalize((uniforms.modelToWorld * float4(normals[vertexID], 0.0)).xyz);
    out.color = uniforms.color;
    return out;
}

fragment float4 popinvr_hand_fragment(HandVertexOut in [[stage_in]]) {
    float3 lightDirection = normalize(float3(-0.35, 0.75, -0.55));
    float diffuse = max(dot(normalize(in.normal), lightDirection), 0.18);
    float3 lit = in.color.rgb * diffuse;
    return float4(lit, in.color.a);
}
