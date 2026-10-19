import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The redraw of a changed area after a removal (architecture.md 5.2, D-66). The drawable has
/// 400 x 240 pixels at scale 2, so the texture shows 400 x 240 canvas points at zoom 1.
@MainActor
@Suite("Redraw of a changed area")
struct RedrawTests {
    private let camera = Camera(center: .zero, zoom: 1)

    /// Two diagonals and a line across both, all through the center.
    private static let crossing = [
        StrokeBuilder.stroke(
            diagonal(from: Point(x: -80, y: -60), to: Point(x: 80, y: 60)),
            seed: 1
        ),
        StrokeBuilder.stroke(diagonal(from: Point(x: -90, y: 5), to: Point(x: 90, y: -5)), seed: 2),
        StrokeBuilder.stroke(
            diagonal(from: Point(x: -80, y: 60), to: Point(x: 80, y: -60)),
            seed: 3
        ),
    ]

    private static func diagonal(from start: Point, to end: Point) -> [Point] {
        (0...40).map { index in
            let t = Double(index) / 40
            return Point(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    private struct Subject {
        let layer: CommittedLayer
        let store: StrokeStore
        let encoder: InkEncoder
        let resources: InkResources

        /// Runs one frame of the layer with `body` and waits for the GPU.
        func runFrame(_ number: UInt64, _ body: (FrameContext) -> Void) throws {
            let commandBuffer = try #require(resources.queue.makeCommandBuffer())
            let context = FrameContext(commandBuffer: commandBuffer, frame: number)
            encoder.beginFrame(context)
            body(context)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        /// Returns the coverage of the front texture.
        func frontCoverage() throws -> [UInt8] {
            let texture = try #require(layer.front?.texture)
            let copy = try resources.makeTarget(
                width: texture.width,
                height: texture.height,
                format: InkResources.committedFormat,
                isReadable: true
            )
            let commandBuffer = try #require(resources.queue.makeCommandBuffer())
            let blit = try #require(commandBuffer.makeBlitCommandEncoder())
            blit.copy(from: texture, to: copy)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return CoverageReader.pixels(of: copy)
        }
    }

    private func makeSubject(_ strokes: [Stroke]) throws -> Subject {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let layer = try CommittedLayer(
            resources: resources,
            drawableWidth: 400,
            drawableHeight: 240
        )
        let store = StrokeStore(
            arena: try PointArena(device: device, initialSlabs: 1, byteBudget: 1 << 20)
        )
        let ring = try DrawListRing(device: device, capacity: 64)
        let encoder = InkEncoder(resources: resources, store: store, ring: ring)
        for stroke in strokes {
            store.add(stroke)
        }
        return Subject(layer: layer, store: store, encoder: encoder, resources: resources)
    }

    /// Builds the front texture in one frame.
    private func build(_ subject: Subject) throws {
        #expect(
            subject.layer.startBuildIfNeeded(camera: camera, displayScale: 2, store: subject.store)
        )
        try subject.runFrame(1) { context in
            subject.layer.continueBuild(encoder: subject.encoder, context: context, budget: .max)
        }
        #expect(!subject.layer.isBuilding)
    }

    /// Returns the coverage of a fresh build of `strokes`.
    private func coverage(of strokes: [Stroke]) throws -> [UInt8] {
        let subject = try makeSubject(strokes)
        try build(subject)
        return try subject.frontCoverage()
    }

    @Test("Removing the middle of three crossing strokes keeps every pixel of the other two")
    func removeMiddle() throws {
        let subject = try makeSubject(Self.crossing)
        try build(subject)
        let middle = Self.crossing[1]
        let area = try #require(subject.store.bounds(of: middle.id))
        #expect(subject.store.remove(middle.id, frame: 2))
        try subject.runFrame(2) { context in
            subject.layer.redraw(
                area,
                store: subject.store,
                encoder: subject.encoder,
                context: context
            )
        }
        let result = try subject.frontCoverage()
        let expected = try coverage(of: [Self.crossing[0], Self.crossing[2]])
        #expect(CoverageReader.largestDifference(result, expected) <= 1)
        #expect(result != (try coverage(of: Self.crossing)))
        let texture = try #require(subject.layer.front?.texture)
        Snapshot.assertMatches(
            RenderedImage(
                width: texture.width,
                height: texture.height,
                pixels: result.flatMap { [$0, $0, $0, 255] }
            ),
            named: "redraw-remove-middle"
        )
    }

    @Test("A stroke removed during a build is not in the finished build", arguments: [0, 1, 2])
    func removeDuringBuild(index: Int) throws {
        let subject = try makeSubject(Self.crossing)
        #expect(
            subject.layer.startBuildIfNeeded(camera: camera, displayScale: 2, store: subject.store)
        )
        try subject.runFrame(1) { context in
            subject.layer.continueBuild(encoder: subject.encoder, context: context, budget: 1)
        }
        #expect(subject.layer.isBuilding)
        let removed = Self.crossing[index]
        let area = try #require(subject.store.bounds(of: removed.id))
        #expect(subject.store.remove(removed.id, frame: 2))
        try subject.runFrame(2) { context in
            subject.layer.redraw(
                area,
                store: subject.store,
                encoder: subject.encoder,
                context: context
            )
        }
        for frame in UInt64(3)...6 where subject.layer.isBuilding {
            try subject.runFrame(frame) { context in
                subject.layer.continueBuild(encoder: subject.encoder, context: context, budget: 1)
            }
        }
        #expect(!subject.layer.isBuilding)
        let remaining = Self.crossing.filter { $0.id != removed.id }
        #expect(
            CoverageReader.largestDifference(
                try subject.frontCoverage(),
                try coverage(of: remaining)
            )
                <= 1
        )
    }

    @Test("An area outside the texture gives no scissor, and a partial area is clipped")
    func scissor() throws {
        let subject = try makeSubject([])
        try build(subject)
        let front = try #require(subject.layer.front)
        let outside = Rect(minX: 1_000, minY: 0, maxX: 1_010, maxY: 10)
        #expect(CommittedLayer.scissor(for: outside, in: front) == nil)
        let edge = try #require(
            CommittedLayer.scissor(
                for: Rect(minX: -500, minY: -10, maxX: -190, maxY: 10),
                in: front
            )
        )
        #expect(edge.x == 0)
        #expect(edge.width == Int(2 * 10 + CommittedLayer.redrawMarginPixels))
    }

    @Test("A redraw of an area shows the added parts there and keeps the ink outside")
    func areaRedraw() throws {
        let subject = try makeSubject(Self.crossing)
        try build(subject)
        let cut = Self.crossing[1]
        // The parts of the middle line outside the strip -10...10, as an erase leaves them.
        let left = StrokeBuilder.stroke(
            Self.diagonal(from: Point(x: -90, y: 5), to: Point(x: -12, y: 0.5)),
            seed: 4
        )
        let right = StrokeBuilder.stroke(
            Self.diagonal(from: Point(x: 12, y: -0.5), to: Point(x: 90, y: -5)),
            seed: 5
        )
        #expect(subject.store.remove(cut.id, frame: 2))
        subject.store.add(left)
        subject.store.add(right)
        let area = Rect(minX: -10, minY: -120, maxX: 10, maxY: 120)
        try subject.runFrame(2) { context in
            subject.layer.redraw(
                area,
                store: subject.store,
                encoder: subject.encoder,
                context: context
            )
        }
        let result = try subject.frontCoverage()
        let expected = try coverage(of: [Self.crossing[0], Self.crossing[2], left, right])
        let texture = try #require(subject.layer.front?.texture)
        // Inside the strip, the result equals a fresh build. Outside it, the old line stays.
        let pixels = 2.0
        let low = Int((Double(texture.width) / 2 + area.minX * pixels).rounded(.down))
        let high = Int((Double(texture.width) / 2 + area.maxX * pixels).rounded(.up))
        var largest = 0
        for row in 0..<texture.height {
            for column in low..<high {
                let index = row * texture.width + column
                largest = max(largest, abs(Int(result[index]) - Int(expected[index])))
            }
        }
        #expect(largest <= 1)
    }
}
