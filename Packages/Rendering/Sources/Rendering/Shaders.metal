#include <metal_stdlib>
using namespace metal;

// The layouts match StrokeDrawEntry, InkUniforms, and CompositeUniforms in ShaderTypes.swift.

// One level-of-detail run of a stroke in the draw list. 32 bytes.
struct StrokeDrawEntry {
    float2 origin;        // stroke origin minus the reference point, canvas points
    uint firstPoint;      // index of the first point of the run in the arena
    uint pointCount;      // control points of the run
    uint firstSegment;    // run start in bits 0-13, previous offset in bits 14-25; see packStart
    uint detail;          // stride, pieces - 1, and next offset; see StrokeDrawEntry.packDetail
    uint firstInstance;   // the first instance of the run in this draw
    float radius;         // half the line width, canvas points
};

// The unpacked level of detail of a run.
struct RunDetail {
    int stride;           // step between used control points
    uint pieces;          // pieces per segment
    int nextOffset;       // from the last point of the run to the next point; 0 at the end
    int previousOffset;   // from the first point of the run back to the point before; 0 at start
};

static RunDetail unpackDetail(uint detail, uint firstSegment) {
    RunDetail run;
    run.previousOffset = int((firstSegment >> 14) & 0xFFFu);
    run.stride = int(detail & 0xFFFu);
    run.pieces = ((detail >> 12) & 0x1Fu) + 1u;
    run.nextOffset = int((detail >> 17) & 0xFFFu);
    return run;
}

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

// Used control point j of a run. Before the first point and after the last point of the
// stroke, it is the mirrored phantom point (D-26). At a boundary between two runs, it is the
// real neighbor point of the stroke at the stride of the neighbor run, so that the curves of
// the two runs meet exactly (docs/m2-fix-plan.md, phase 3, task 2).
static float2 controlPoint(const device float4 *points, StrokeDrawEntry entry, RunDetail run,
                           int j) {
    int last = int(entry.pointCount) - 1;
    int used = (last + run.stride - 1) / run.stride + 1;
    if (j < 0 && run.previousOffset > 0) {
        return points[int(entry.firstPoint) - run.previousOffset].xy;
    }
    if (j < 0) {
        float2 first = points[entry.firstPoint].xy;
        float2 second = points[entry.firstPoint + uint(min(run.stride, last))].xy;
        return 2.0 * first - second;
    }
    if (j >= used && run.nextOffset > 0) {
        return points[entry.firstPoint + uint(last + run.nextOffset)].xy;
    }
    if (j >= used) {
        float2 end = points[entry.firstPoint + uint(last)].xy;
        float2 before = points[entry.firstPoint + uint(min((used - 2) * run.stride, last))].xy;
        return 2.0 * end - before;
    }
    return points[entry.firstPoint + uint(min(j * run.stride, last))].xy;
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
    RunDetail run = unpackDetail(entry.detail, entry.firstSegment);
    uint local = instanceID - entry.firstInstance;
    int segment = int(local / run.pieces);
    float piece = float(local % run.pieces);
    float2 p0 = controlPoint(points, entry, run, segment - 1);
    float2 p1 = controlPoint(points, entry, run, segment);
    float2 p2 = controlPoint(points, entry, run, segment + 1);
    float2 p3 = controlPoint(points, entry, run, segment + 2);
    float t0 = piece / float(run.pieces);
    float t1 = (piece + 1.0) / float(run.pieces);
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
