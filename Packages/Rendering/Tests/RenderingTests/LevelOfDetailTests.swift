import Testing

@testable import Rendering

@Suite("Level of detail")
struct LevelOfDetailTests {
    @Test("Points that are far apart on the screen are all used")
    func fullDetail() {
        let detail = LevelOfDetail(
            pointCount: 300,
            meanSpacing: 2,
            maxSpacing: 3,
            pixelsPerCanvasPoint: 2
        )
        #expect(detail.stride == 1)
        #expect(detail.effectivePointCount == 300)
        #expect(detail.piecesPerSegment == 1)
        #expect(detail.instanceCount == 299)
    }

    @Test("At low zoom, used points are at least one pixel apart")
    func lowZoom() {
        let detail = LevelOfDetail(
            pointCount: 300,
            meanSpacing: 0.25,
            maxSpacing: 0.5,
            pixelsPerCanvasPoint: 0.5
        )
        #expect(detail.stride == 8)
        #expect(detail.effectivePointCount == 39)
        #expect(Double(detail.stride) * 0.25 * 0.5 >= LevelOfDetail.minimumPixelSpacing)
    }

    @Test("At high zoom, segments split into pieces up to the limit")
    func highZoom() {
        let some = LevelOfDetail(
            pointCount: 10,
            meanSpacing: 2,
            maxSpacing: 3,
            pixelsPerCanvasPoint: 16
        )
        #expect(some.piecesPerSegment == 8)
        let many = LevelOfDetail(
            pointCount: 10,
            meanSpacing: 50,
            maxSpacing: 100,
            pixelsPerCanvasPoint: 16
        )
        #expect(many.piecesPerSegment == LevelOfDetail.maxPiecesPerSegment)
    }

    @Test("A dot draws one segment")
    func dot() {
        let detail = LevelOfDetail(
            pointCount: 2,
            meanSpacing: 0,
            maxSpacing: 0,
            pixelsPerCanvasPoint: 2
        )
        #expect(detail.stride == 1)
        #expect(detail.effectivePointCount == 2)
        #expect(detail.instanceCount == 1)
    }

    @Test("The last point is always used")
    func lastPoint() {
        let detail = LevelOfDetail(
            pointCount: 11,
            meanSpacing: 0.1,
            maxSpacing: 0.1,
            pixelsPerCanvasPoint: 1,
            minimumPixelSpacing: 0.5
        )
        #expect(detail.stride == 5)
        #expect(detail.effectivePointCount == 3)
    }
}
