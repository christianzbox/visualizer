#include <metal_stdlib>
using namespace metal;

struct SpectraVertex {
    float2 position;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut spectra_vertex(uint vertexID [[vertex_id]],
                                constant SpectraVertex *vertices [[buffer(0)]]) {
    VertexOut out;
    SpectraVertex vertex = vertices[vertexID];
    out.position = float4(vertex.position, 0.0, 1.0);
    out.color = vertex.color;
    return out;
}

fragment half4 spectra_fragment(VertexOut in [[stage_in]]) {
    return half4(in.color);
}
