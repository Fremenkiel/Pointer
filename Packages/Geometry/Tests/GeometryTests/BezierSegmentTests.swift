import Testing

@testable import Geometry

@Suite("Bézier segments of a stroke curve")
struct BezierSegmentTests {
    /// The parameters per segment that the tests compare, the ends included.
    private static let samplesPerSegment = 33

    /// Makes a curve of `count` control points on a wavy path.
    private static func curve(count: Int) -> StrokeCurve {
        let points = (0..<count).map { index in
            let t = Double(index)
            return Point(x: t * 7.5 + 0.25 * t * t, y: 40 * (t * 0.37).sinApproximation + t)
        }
        return StrokeCurve(controlPoints: points)
    }

    @Test("Each Bézier segment matches the B-spline", arguments: [2, 3, 300])
    func matchesTheBSpline(count: Int) {
        let curve = Self.curve(count: count)
        var largest = 0.0
        for index in 0..<curve.segmentCount {
            let segment = curve.bezierSegment(at: index)
            for step in 0..<Self.samplesPerSegment {
                let local = Double(step) / Double(Self.samplesPerSegment - 1)
                let expected = curve.point(at: Double(index) + local)
                let actual = segment.point(at: local)
                largest = max(largest, abs(actual.x - expected.x), abs(actual.y - expected.y))
            }
        }
        #expect(largest < 1e-9, "The largest distance is \(largest)")
    }

    @Test("The segments start and end at the end control points", arguments: [2, 3, 300])
    func endPoints(count: Int) {
        let curve = Self.curve(count: count)
        let first = curve.bezierSegment(at: 0).start
        let last = curve.bezierSegment(at: curve.segmentCount - 1).end
        #expect(abs(first.x - curve.controlPoints[0].x) < 1e-9)
        #expect(abs(first.y - curve.controlPoints[0].y) < 1e-9)
        #expect(abs(last.x - curve.controlPoints[count - 1].x) < 1e-9)
        #expect(abs(last.y - curve.controlPoints[count - 1].y) < 1e-9)
    }

    @Test("Neighbor segments meet", arguments: [3, 300])
    func neighborsMeet(count: Int) {
        let curve = Self.curve(count: count)
        for index in 1..<curve.segmentCount {
            let end = curve.bezierSegment(at: index - 1).end
            let start = curve.bezierSegment(at: index).start
            #expect(abs(end.x - start.x) < 1e-9 && abs(end.y - start.y) < 1e-9)
        }
    }

    /// The segment index and whether the precondition holds, for a curve of 5 points.
    private static let indices: [(Int, Bool)] = [(0, true), (3, true), (4, false)]

    @Test("The segment index must be a segment of the curve", arguments: indices)
    func segmentIndex(index: Int, isValid: Bool) async {
        if isValid {
            #expect(Self.curve(count: 5).bezierSegment(at: index).start.isFinite)
        } else {
            await #expect(processExitsWith: .failure) { [index] in
                _ = BezierSegmentTests.curve(count: 5).bezierSegment(at: index)
            }
        }
    }

    @Test("The Bézier parameter must be in 0 to 1", arguments: [-0.5, 1.5])
    func parameterRange(local: Double) async {
        await #expect(processExitsWith: .failure) { [local] in
            let segment = BezierSegment(
                start: .zero,
                control1: .zero,
                control2: .zero,
                end: .zero
            )
            _ = segment.point(at: local)
        }
    }
}

extension Double {
    /// A smooth wave without Foundation, for the test curves: a parabola per half period.
    fileprivate var sinApproximation: Double {
        let period = 2.0
        let phase = self - period * (self / period).rounded(.down)
        return phase < 1 ? 4 * phase * (1 - phase) : -4 * (phase - 1) * (2 - phase)
    }
}
