#include <metal_stdlib>
using namespace metal;

// One capsule: a segment with round ends, in canvas points. 20 bytes, matches `Capsule` in Swift.
struct Capsule {
    packed_float2 start;
    packed_float2 end;
    float radius;
};

struct Uniforms {
    float2 viewSize;   // view points
    float zoom;        // view points per canvas point
    float pixelSize;   // one device pixel in canvas points
};

struct VertexOut {
    float4 position [[position]];
    float2 canvas;
    float2 start [[flat]];
    float2 end [[flat]];
    float radius [[flat]];
};

vertex VertexOut capsuleVertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               const device Capsule *capsules [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
    Capsule c = capsules[iid];
    float2 a = float2(c.start);
    float2 b = float2(c.end);
    float2 d = b - a;
    float len = length(d);
    float2 dir = len > 1e-6 ? d / len : float2(1, 0);
    float2 nrm = float2(-dir.y, dir.x);
    float pad = c.radius + u.pixelSize;
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    float2 p = (corner.x < 0 ? a - dir * pad : b + dir * pad) + nrm * pad * corner.y;
    float2 view = p * u.zoom;
    VertexOut out;
    out.position = float4(view.x / u.viewSize.x * 2.0 - 1.0, 1.0 - view.y / u.viewSize.y * 2.0, 0, 1);
    out.canvas = p;
    out.start = a;
    out.end = b;
    out.radius = c.radius;
    return out;
}

fragment float4 capsuleFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    float2 pa = in.canvas - in.start;
    float2 ba = in.end - in.start;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12), 0.0, 1.0);
    float dist = length(pa - ba * h);
    float coverage = clamp((in.radius - dist) / u.pixelSize + 0.5, 0.0, 1.0);
    return float4(coverage, coverage, coverage, coverage);
}
