import Testing

@testable import Geometry

@Suite("Stroke curve")
struct StrokeCurveTests {
    /// The control points and the `PKStrokePath.interpolatedLocation(at:)` values that the
    /// PencilKit probe of docs/m2-plan.md section 1 printed.
    private let controlPoints = [
        Point(x: 0, y: 0), Point(x: 10, y: 30), Point(x: 40, y: 35),
        Point(x: 60, y: 0), Point(x: 90, y: 10), Point(x: 100, y: 50),
    ]
    // swiftlint:disable:next large_tuple
    private static let pencilKitValues: [(Double, Double, Double)] = [
        (0.0, 0.0, 0.0), (0.25, 2.5521, 7.4349), (0.5, 5.4167, 14.4792), (1.0, 13.3333, 25.8333),
        (1.75, 31.8490, 30.8724), (2.5, 50.0, 17.6042), (3.25, 68.1510, 5.7422),
        (4.0, 86.6667, 15.0), (4.75, 97.4479, 40.0781), (5.0, 100.0, 50.0),
    ]

    @Test("The curve matches the PencilKit values", arguments: pencilKitValues)
    func matchesPencilKit(parameter: Double, x: Double, y: Double) {
        let point = StrokeCurve(controlPoints: controlPoints).point(at: parameter)
        #expect(abs(point.x - x) < 0.001)
        #expect(abs(point.y - y) < 0.001)
    }

    @Test("The curve passes through both end points")
    func endPoints() {
        let curve = StrokeCurve(controlPoints: controlPoints)
        #expect(curve.point(at: 0) == controlPoints[0])
        let end = curve.point(at: Double(curve.segmentCount))
        #expect(abs(end.x - 100) < 1e-9)
        #expect(abs(end.y - 50) < 1e-9)
    }

    @Test("Two control points give a straight line")
    func twoPoints() {
        let curve = StrokeCurve(controlPoints: [Point(x: 0, y: 0), Point(x: 10, y: 0)])
        #expect(curve.segmentCount == 1)
        let middle = curve.point(at: 0.5)
        #expect(abs(middle.x - 5) < 1e-9)
        #expect(middle.y == 0)
    }

    @Test("The phantom points mirror the second point through each end point")
    func phantoms() {
        let curve = StrokeCurve(controlPoints: controlPoints)
        #expect(curve.extendedControlPoint(at: -1) == Point(x: -10, y: -30))
        #expect(curve.extendedControlPoint(at: 6) == Point(x: 110, y: 90))
        #expect(curve.extendedControlPoint(at: 2) == Point(x: 40, y: 35))
    }

    @Test("The segment weights sum to one")
    func weights() {
        let point = StrokeCurve.evaluate(
            Point(x: 1, y: 1),
            Point(x: 1, y: 1),
            Point(x: 1, y: 1),
            Point(x: 1, y: 1),
            0.3
        )
        #expect(abs(point.x - 1) < 1e-12)
        #expect(abs(point.y - 1) < 1e-12)
    }
}
