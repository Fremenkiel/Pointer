import Model
import Testing

@testable import Rendering

@Suite("Level-of-detail runs")
struct DetailRunsTests {
    /// Points along x, `spacing` apart, with one jump of `jump` canvas points after `jumpIndex`.
    private func points(
        count: Int,
        spacing: Float,
        jump: Float = 0,
        jumpIndex: Int = -1
    ) -> InkPoints {
        var x: Float = 0
        let values = (0..<count).map { index -> InkPoint in
            if index > 0 { x += index == jumpIndex + 1 ? jump : spacing }
            return InkPoint(x: x, y: 0, force: -1, time: Float(index) / 240)
        }
        return InkPoints(values)
    }

    private func runs(of points: InkPoints, pixelsPerCanvasPoint: Double) -> [DetailRun] {
        var spacings: [SIMD2<Float>] = []
        DetailRuns.appendSpacings(of: points, to: &spacings)
        var result: [DetailRun] = []
        DetailRuns.forEach(
            pointCount: points.count,
            spacings: spacings[...],
            pixelsPerCanvasPoint: pixelsPerCanvasPoint,
            minimumPixelSpacing: LevelOfDetail.minimumPixelSpacing
        ) { result.append($0) }
        return result
    }

    @Test(
        "A stroke has one block per 64 segments",
        arguments: [(2, 1), (65, 1), (66, 2), (300, 5)]
    )
    func blockCount(pointCount: Int, blocks: Int) {
        #expect(DetailRuns.blockCount(pointCount: pointCount) == blocks)
    }

    @Test("A uniform stroke is one run with the level of detail of the whole stroke")
    func uniformStroke() {
        let stroke = points(count: 300, spacing: 0.0625)
        let result = runs(of: stroke, pixelsPerCanvasPoint: 0.5)
        let whole = LevelOfDetail(
            pointCount: 300,
            meanSpacing: 0.0625,
            maxSpacing: 0.0625,
            pixelsPerCanvasPoint: 0.5
        )
        #expect(result.count == 1)
        #expect(result.first?.start == 0)
        #expect(result.first?.end == 299)
        #expect(result.first?.stride == whole.stride)
        #expect(result.first?.instanceCount == whole.instanceCount)
    }

    @Test("One long segment no longer sets the pieces of the whole stroke")
    func longSegment() {
        let stroke = points(count: 1_000, spacing: 0.001, jump: 100, jumpIndex: 500)
        let result = runs(of: stroke, pixelsPerCanvasPoint: 16)
        let total = result.reduce(0) { $0 + $1.instanceCount }
        #expect(total <= 2_100)
        #expect(result.count > 1)
    }

    @Test("The runs cover the stroke without a gap")
    func coverage() {
        let stroke = points(count: 1_000, spacing: 0.001, jump: 100, jumpIndex: 500)
        let result = runs(of: stroke, pixelsPerCanvasPoint: 16)
        #expect(result.first?.start == 0)
        #expect(result.last?.end == 999)
        for (previous, next) in zip(result, result.dropFirst()) {
            #expect(previous.end == next.start)
        }
    }

    @Test("Neighbor offsets use the strides of the neighbor runs, and 0 at the stroke ends")
    func neighborOffsets() {
        let stroke = points(count: 1_000, spacing: 0.001, jump: 100, jumpIndex: 500)
        let result = runs(of: stroke, pixelsPerCanvasPoint: 16)
        #expect(result.first?.previousOffset == 0)
        #expect(result.last?.nextOffset == 0)
        for (previous, next) in zip(result, result.dropFirst()) {
            #expect(previous.nextOffset == min(next.stride, 999 - previous.end))
            #expect(next.previousOffset == min(previous.stride, next.start))
        }
    }

    @Test("The start value packs the start and the previous offset")
    func startPacking() {
        let packed = StrokeDrawEntry.packStart(start: 16_383, previousOffset: 4_095)
        #expect(packed & 0x3FFF == 16_383)
        #expect((packed >> 14) & 0xFFF == 4_095)
    }

    @Test("The detail value packs the stride, the pieces, and the next offset")
    func packing() {
        let packed = StrokeDrawEntry.packDetail(stride: 63, pieces: 32, nextOffset: 7)
        #expect(packed & 0xFFF == 63)
        #expect((packed >> 12) & 0x1F == 31)
        #expect((packed >> 17) & 0xFFF == 7)
    }
}
