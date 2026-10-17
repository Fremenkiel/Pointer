import Geometry
import Model
import XCTest

@testable import Rendering

/// The GPU time of one full content pass for each level-of-detail spacing, with an image
/// comparison against the M2 spacing (docs/m2-fix-plan.md, phase 0, task 6). The GPU times are
/// valid on a device only, so the simulator skips these tests.
@MainActor
final class LevelOfDetailPerformanceTests: XCTestCase {
    /// The spacings to compare. The first one is the M2 value and gives the reference image.
    private static let spacings = [0.5, 0.75, 1.0]
    /// The largest pixel difference of M2 acceptance 4.
    private static let maxDifference = 17
    /// The texture of the committed layer on the iPad Pro 11-inch: twice the drawable.
    private static let textureWidth = 4840
    private static let textureHeight = 3336
    /// The timed passes per spacing, after the warm-up passes.
    private static let timedPasses = 7
    private static let warmUpPasses = 5

    func testDenseStrokesAtQuarterZoom() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        try compare(content, camera: Camera(center: .zero, zoom: 0.25), name: "dense z0.25")
    }

    func testDenseStrokesAtZoomOne() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        try compare(content, camera: Camera(center: .zero, zoom: 1), name: "dense z1")
    }

    func testHandwritingAtQuarterZoom() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        try compare(content, camera: Camera(center: .zero, zoom: 0.25), name: "handwriting z0.25")
    }

    func testHandwritingAtZoomOne() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        try compare(content, camera: Camera(center: .zero, zoom: 1), name: "handwriting z1")
    }

    func testHandwritingAtZoomEight() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        let camera = Camera(center: Point(x: -100, y: -100), zoom: 8)
        try compare(content, camera: camera, name: "handwriting z8")
    }

    private func compare(_ content: [Stroke], camera: Camera, name: String) throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("GPU times are valid on a device only.")
        #else
            let rig = try InkRig(strokes: content)
            let texture = try rig.resources.makeTarget(
                width: Self.textureWidth,
                height: Self.textureHeight,
                format: .r8Unorm,
                isReadable: true
            )
            let target = InkTarget(texture: texture, camera: camera, displayScale: 2)
            let slots = rig.visibleSlots(of: target)
            // The GPU clock ramps up during the first passes of a test, so the first run only
            // warms it up.
            _ = medianTime(rig: rig, slots: slots, target: target)
            var reference: [UInt8]?
            for spacing in Self.spacings {
                rig.encoder.minimumPixelSpacing = spacing
                let time = medianTime(rig: rig, slots: slots, target: target)
                let image = CoverageReader.pixels(of: texture)
                let difference = CoverageReader.largestDifference(reference ?? image, image)
                reference = reference ?? image
                let instances = rig.instanceCount(slots: slots, target: target)
                let line = String(
                    format: "%@ at %.2f px: %d strokes, %d instances, %.2f GPU ms, diff %d",
                    name,
                    spacing,
                    slots.count,
                    instances,
                    time,
                    difference
                )
                XCTContext.runActivity(named: line) { _ in }
                XCTAssertLessThanOrEqual(difference, Self.maxDifference, line)
            }
        #endif
    }

    /// The passes run back to back, so that the GPU keeps its clock between them. The span from
    /// the first timed pass to the last one counts each overlap once.
    private func medianTime(rig: InkRig, slots: [Int], target: InkTarget) -> Double {
        let buffers = (0..<(Self.warmUpPasses + Self.timedPasses)).map { _ in
            rig.commitPass(slots: slots, target: target)
        }
        buffers.last?.waitUntilCompleted()
        let first = buffers[Self.warmUpPasses]
        let last = buffers[buffers.count - 1]
        return (last.gpuEndTime - first.gpuStartTime) * 1000 / Double(Self.timedPasses)
    }
}
