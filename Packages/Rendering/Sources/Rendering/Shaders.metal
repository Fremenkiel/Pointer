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
    float4 background;    // canvas color in sRGB, alpha 1 (D-106)
};

// One eraser stamp: a capsule from one sample to the next, in mask pixels (D-66). 32 bytes.
struct EraserStamp {
    float2 start;
    float2 end;
    float2 targetSize;    // pixels
    float radius;         // pixels
    float edge;           // half width of the edge ramp, pixels
};

// One glyph quad of the text pass, in target pixels and atlas pixels (D-29). 32 bytes.
struct GlyphInstance {
    float2 position;      // top-left corner in the target, pixels
    float2 size;          // size in the target, pixels
    float2 atlasOrigin;   // top-left corner in the atlas page, pixels
    float2 atlasSize;     // size in the atlas page, pixels
};

struct GlyphUniforms {
    float2 targetSize;    // pixels
    float2 atlasSize;     // pixels of the atlas page
};

struct GlyphVertexOut {
    float4 position [[position]];
    float2 atlasPoint;    // atlas pixels
};

struct CardBorderVertexOut {
    float4 position [[position]];
    float2 center [[flat]];      // target pixels
    float2 halfSize [[flat]];    // target pixels
    float halfWidth [[flat]];    // half the line width, pixels
    float radius [[flat]];       // corner radius, pixels
    float coverage [[flat]];     // the gray of the border (D-96)
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
static float2 controlPoint(const device float2 *points, StrokeDrawEntry entry, RunDetail run,
                           int j) {
    int last = int(entry.pointCount) - 1;
    int used = (last + run.stride - 1) / run.stride + 1;
    if (j < 0 && run.previousOffset > 0) {
        return points[int(entry.firstPoint) - run.previousOffset];
    }
    if (j < 0) {
        float2 first = points[entry.firstPoint];
        float2 second = points[entry.firstPoint + uint(min(run.stride, last))];
        return 2.0 * first - second;
    }
    if (j >= used && run.nextOffset > 0) {
        return points[entry.firstPoint + uint(last + run.nextOffset)];
    }
    if (j >= used) {
        float2 end = points[entry.firstPoint + uint(last)];
        float2 before = points[entry.firstPoint + uint(min((used - 2) * run.stride, last))];
        return 2.0 * end - before;
    }
    return points[entry.firstPoint + uint(min(j * run.stride, last))];
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
                              const device float2 *points [[buffer(0)]],
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

// White ink and text on the canvas color: the larger coverage of the two channels is the weight
// of white (D-106). The mix runs on the stored sRGB values, as Core Animation blends the live
// PencilKit canvas on top, so full coverage stays 255 (D-38).
fragment float4 compositeFragment(CompositeVertexOut in [[stage_in]],
                                  texture2d<float> committed [[texture(0)]],
                                  constant CompositeUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(address::clamp_to_zero, filter::linear);
    float2 texel = in.position.xy * uniforms.scale + uniforms.offset;
    float2 coverage = committed.sample(linearSampler, texel / uniforms.textureSize).rg;
    float value = max(coverage.r, coverage.g);
    return float4(mix(uniforms.background.rgb, float3(1.0), value), 1.0);
}

// Zero coverage. With a scissor rectangle, it clears one area of a committed texture (D-66).
fragment half4 clearFragment(CompositeVertexOut in [[stage_in]]) {
    return half4(0.0);
}

// The capsule of one eraser stamp on a quad, like one piece of ink.
vertex InkVertexOut eraserVertex(uint vertexID [[vertex_id]],
                                 constant EraserStamp &stamp [[buffer(0)]]) {
    float2 a = stamp.start;
    float2 b = stamp.end;
    float2 delta = b - a;
    float len = length(delta);
    float2 direction = len > 1e-6 ? delta / len : float2(1.0, 0.0);
    float2 normal = float2(-direction.y, direction.x);
    float pad = stamp.radius + stamp.edge + 1.0;
    float2 corner = float2((vertexID & 1) ? 1.0 : -1.0, (vertexID & 2) ? 1.0 : -1.0);
    float2 pixel = (corner.x < 0.0 ? a - direction * pad : b + direction * pad) + normal * pad * corner.y;

    InkVertexOut out;
    out.position = float4(pixel.x / stamp.targetSize.x * 2.0 - 1.0,
                          1.0 - pixel.y / stamp.targetSize.y * 2.0, 0.0, 1.0);
    out.start = a;
    out.end = b;
    out.radius = stamp.radius;
    return out;
}

// The coverage of an eraser stamp, with the same edge as the ink.
fragment half4 eraserFragment(InkVertexOut in [[stage_in]], constant EraserStamp &stamp [[buffer(0)]]) {
    float2 pa = in.position.xy - in.start;
    float2 ba = in.end - in.start;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    float distanceToEdge = length(pa - ba * h) - in.radius;
    return half4(1.0 - smoothstep(-stamp.edge, stamp.edge, distanceToEdge));
}

// The composite pass while the eraser moves: the mask hides the ink under the stamps (D-66).
// The text channel stays, because the eraser removes ink only (D-82).
// The mask has the size and the mapping of the committed texture.
fragment float4 compositeMaskedFragment(CompositeVertexOut in [[stage_in]],
                                        texture2d<float> committed [[texture(0)]],
                                        texture2d<float> mask [[texture(1)]],
                                        constant CompositeUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(address::clamp_to_zero, filter::linear);
    float2 texel = (in.position.xy * uniforms.scale + uniforms.offset) / uniforms.textureSize;
    float2 coverage = committed.sample(linearSampler, texel).rg;
    float ink = coverage.r * (1.0 - mask.sample(linearSampler, texel).r);
    float value = max(ink, coverage.g);
    return float4(mix(uniforms.background.rgb, float3(1.0), value), 1.0);
}

// One glyph of the text pass: a quad that shows its bitmap from the atlas page.
vertex GlyphVertexOut glyphVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                  constant GlyphInstance *glyphs [[buffer(0)]],
                                  constant GlyphUniforms &uniforms [[buffer(1)]]) {
    GlyphInstance glyph = glyphs[instanceID];
    float2 corner = float2((vertexID & 1) ? 1.0 : 0.0, (vertexID & 2) ? 1.0 : 0.0);
    float2 pixel = glyph.position + corner * glyph.size;
    GlyphVertexOut out;
    out.position = float4(pixel.x / uniforms.targetSize.x * 2.0 - 1.0,
                          1.0 - pixel.y / uniforms.targetSize.y * 2.0, 0.0, 1.0);
    out.atlasPoint = glyph.atlasOrigin + corner * glyph.atlasSize;
    return out;
}

// The coverage of a glyph from the atlas. The pipeline writes it into the text channel.
fragment half4 glyphFragment(GlyphVertexOut in [[stage_in]],
                             texture2d<float> atlas [[texture(0)]],
                             constant GlyphUniforms &uniforms [[buffer(1)]]) {
    constexpr sampler linearSampler(address::clamp_to_zero, filter::linear);
    float coverage = atlas.sample(linearSampler, in.atlasPoint / uniforms.atlasSize).r;
    return half4(coverage);
}

// The border of one card: a rounded rectangle on a quad that holds the line and its edge (D-96).
// The quad uses the glyph instance: `atlasOrigin` holds the line width and the corner radius in
// pixels, and `atlasSize.x` holds the coverage of the border.
vertex CardBorderVertexOut cardBorderVertex(uint vertexID [[vertex_id]],
                                            uint instanceID [[instance_id]],
                                            constant GlyphInstance *quads [[buffer(0)]],
                                            constant GlyphUniforms &uniforms [[buffer(1)]]) {
    GlyphInstance quad = quads[instanceID];
    float halfWidth = quad.atlasOrigin.x * 0.5;
    float pad = halfWidth + 1.0;
    float2 corner = float2((vertexID & 1) ? 1.0 : 0.0, (vertexID & 2) ? 1.0 : 0.0);
    float2 pixel = quad.position - pad + corner * (quad.size + 2.0 * pad);
    CardBorderVertexOut out;
    out.position = float4(pixel.x / uniforms.targetSize.x * 2.0 - 1.0,
                          1.0 - pixel.y / uniforms.targetSize.y * 2.0, 0.0, 1.0);
    out.halfSize = quad.size * 0.5;
    out.center = quad.position + out.halfSize;
    out.halfWidth = halfWidth;
    out.radius = min(quad.atlasOrigin.y, min(out.halfSize.x, out.halfSize.y));
    out.coverage = quad.atlasSize.x;
    return out;
}

// The coverage of the border line: the distance to the rounded rectangle, with a one-pixel edge.
fragment half4 cardBorderFragment(CardBorderVertexOut in [[stage_in]]) {
    float2 q = abs(in.position.xy - in.center) - (in.halfSize - in.radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - in.radius;
    float line = clamp(in.halfWidth + 0.5 - abs(distance), 0.0, 1.0);
    return half4(line * in.coverage);
}

// The preview of a child canvas: the larger coverage of the two channels in one channel, as the
// composite shows it (D-97). One fragment per pixel, so the image keeps the pixels of the target.
fragment half4 previewResolveFragment(CompositeVertexOut in [[stage_in]],
                                      texture2d<float> committed [[texture(0)]]) {
    float2 coverage = committed.read(uint2(in.position.xy)).rg;
    return half4(max(coverage.r, coverage.g));
}
