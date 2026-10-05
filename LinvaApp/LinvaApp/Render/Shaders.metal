#include <metal_stdlib>
using namespace metal;

struct ViewportUniforms {
    float2 size;
};

struct SolidVertex {
    float2 position;
    float4 color;
};

struct TexturedVertex {
    float2 position;
    float2 textureCoordinate;
    float4 color;
};

struct SolidVertexOut {
    float4 position [[position]];
    half4 color;
};

struct TexturedVertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
    half4 color;
};

static float4 clipPosition(float2 screenPosition, constant ViewportUniforms &viewport) {
    float2 normalized = screenPosition / max(viewport.size, float2(1.0));
    return float4(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0, 0.0, 1.0);
}

vertex SolidVertexOut solidVertex(
    uint vertexId [[vertex_id]],
    const device SolidVertex *vertices [[buffer(0)]],
    constant ViewportUniforms &viewport [[buffer(1)]]
) {
    SolidVertexOut out;
    out.position = clipPosition(vertices[vertexId].position, viewport);
    out.color = half4(vertices[vertexId].color);
    return out;
}

fragment half4 solidFragment(SolidVertexOut in [[stage_in]]) {
    return in.color;
}

vertex TexturedVertexOut texturedVertex(
    uint vertexId [[vertex_id]],
    const device TexturedVertex *vertices [[buffer(0)]],
    constant ViewportUniforms &viewport [[buffer(1)]]
) {
    TexturedVertexOut out;
    out.position = clipPosition(vertices[vertexId].position, viewport);
    out.textureCoordinate = vertices[vertexId].textureCoordinate;
    out.color = half4(vertices[vertexId].color);
    return out;
}

fragment half4 texturedFragment(
    TexturedVertexOut in [[stage_in]],
    texture2d<half> textTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    return textTexture.sample(textureSampler, in.textureCoordinate) * in.color;
}
