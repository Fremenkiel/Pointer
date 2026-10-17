#include <metal_stdlib>
using namespace metal;

// The layouts match StrokeDrawEntry, InkUniforms, and CompositeUniforms in ShaderTypes.swift.

// One stroke in the draw list. 32 bytes.
struct StrokeDrawEntry {
    float2 origin;        // stroke origin minus the reference point, canvas points
    uint firstPoint;      // index of the first point in the arena
    uint pointCount;      // control points of the stroke
    uint stride;          // step between used control points (level of detail)
    uint pieces;          // pieces per segment
    uint firstInstance;   // the first instance of the stroke in this draw
    float radius;         // half the line width, canvas points
};

struct InkUniforms {
    float2 targetSize;    // pixels
    float2 offset;        // pixel position of the reference point
    float scale;          // pixels per canvas point
    uint entryCount;
    float edge;           // half width of the edge ramp, pixels
    float padding;
};

struct CompositeUniforms {
    float2 scale;         // drawable pixel to committed texture pixel
    float2 offset;
    float2 textureSize;   // committed texture, pixels
};

struct InkVertexOut {
    float4 position [[position]];
    float2 start [[flat]];
    float2 end [[flat]];
    float radius [[flat]];
};

// The draw list is sorted by firstInstance, so a binary search finds the stroke of an instance.
static uint findEntry(constant StrokeDrawEntry *entries, uint count, uint instance) {
    uint low = 0;
    uint high = count - 1;
    for (uint step = 0; step < 32 && low < high; ++step) {
        uint middle = (low + high + 1) / 2;
        if (entries[middle].firstInstance <= instance) {
            low = middle;
        } else {
            high = middle - 1;
        }
    }
    return low;
}

// Control point j of the level of detail, with the mirrored phantom point at each end (D-26).
static float2 controlPoint(const device float4 *points, StrokeDrawEntry entry, int j) {
    int last = int(entry.pointCount) - 1;
    int used = (last + int(entry.stride) - 1) / int(entry.stride) + 1;
    if (j < 0) {
        float2 first = points[entry.firstPoint].xy;
        float2 second = points[entry.firstPoint + uint(min(int(entry.stride), last))].xy;
        return 2.0 * first - second;
    }
    if (j >= used) {
        float2 end = points[entry.firstPoint + uint(last)].xy;
        float2 before = points[entry.firstPoint + uint(min((used - 2) * int(entry.stride), last))].xy;
        return 2.0 * end - before;
    }
    return points[entry.firstPoint + uint(min(j * int(entry.stride), last))].xy;
}

static float2 bSpline(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    float inverse = 1.0 - t;
    float w0 = inverse * inverse * inverse / 6.0;
    float w1 = (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0;
    float w2 = (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0;
    float w3 = t3 / 6.0;
    return w0 * p0 + w1 * p1 + w2 * p2 + w3 * p3;
}

// Each instance is one piece of one curve segment, drawn as a capsule on a quad.
vertex InkVertexOut inkVertex(uint vertexID [[vertex_id]],
                              uint instanceID [[instance_id]],
                              const device float4 *points [[buffer(0)]],
                              constant StrokeDrawEntry *entries [[buffer(1)]],
                              constant InkUniforms &uniforms [[buffer(2)]]) {
    StrokeDrawEntry entry = entries[findEntry(entries, uniforms.entryCount, instanceID)];
    uint local = instanceID - entry.firstInstance;
    int segment = int(local / entry.pieces);
    float piece = float(local % entry.pieces);
    float2 p0 = controlPoint(points, entry, segment - 1);
    float2 p1 = controlPoint(points, entry, segment);
    float2 p2 = controlPoint(points, entry, segment + 1);
    float2 p3 = controlPoint(points, entry, segment + 2);
    float t0 = piece / float(entry.pieces);
    float t1 = (piece + 1.0) / float(entry.pieces);
    float2 a = uniforms.offset + (entry.origin + bSpline(p0, p1, p2, p3, t0)) * uniforms.scale;
    float2 b = uniforms.offset + (entry.origin + bSpline(p0, p1, p2, p3, t1)) * uniforms.scale;
    float radius = entry.radius * uniforms.scale;

    float2 delta = b - a;
    float len = length(delta);
    float2 direction = len > 1e-6 ? delta / len : float2(1.0, 0.0);
    float2 normal = float2(-direction.y, direction.x);
    float pad = radius + uniforms.edge + 1.0;
    float2 corner = float2((vertexID & 1) ? 1.0 : -1.0, (vertexID & 2) ? 1.0 : -1.0);
    float2 pixel = (corner.x < 0.0 ? a - direction * pad : b + direction * pad) + normal * pad * corner.y;

    InkVertexOut out;
    out.position = float4(pixel.x / uniforms.targetSize.x * 2.0 - 1.0,
                          1.0 - pixel.y / uniforms.targetSize.y * 2.0, 0.0, 1.0);
    out.start = a;
    out.end = b;
    out.radius = radius;
    return out;
}

// Coverage with the smooth edge of the PencilKit monoline (docs/m2-plan.md section 1, fact 3).
fragment half4 inkFragment(InkVertexOut in [[stage_in]], constant InkUniforms &uniforms [[buffer(2)]]) {
    float2 pa = in.position.xy - in.start;
    float2 ba = in.end - in.start;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    float distanceToEdge = length(pa - ba * h) - in.radius;
    float coverage = 1.0 - smoothstep(-uniforms.edge, uniforms.edge, distanceToEdge);
    return half4(coverage);
}

struct CompositeVertexOut {
    float4 position [[position]];
};

// One triangle that covers the whole target.
vertex CompositeVertexOut compositeVertex(uint vertexID [[vertex_id]]) {
    float2 corner = float2((vertexID == 1) ? 3.0 : -1.0, (vertexID == 2) ? 3.0 : -1.0);
    CompositeVertexOut out;
    out.position = float4(corner, 0.0, 1.0);
    return out;
}

// White ink on black: the coverage of the committed texture becomes the gray value.
fragment float4 compositeFragment(CompositeVertexOut in [[stage_in]],
                                  texture2d<float> committed [[texture(0)]],
                                  constant CompositeUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(address::clamp_to_zero, filter::linear);
    float2 texel = in.position.xy * uniforms.scale + uniforms.offset;
    float value = committed.sample(linearSampler, texel / uniforms.textureSize).r;
    return float4(value, value, value, 1.0);
}
