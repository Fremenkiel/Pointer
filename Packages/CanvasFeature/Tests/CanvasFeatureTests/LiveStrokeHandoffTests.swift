import Geometry
import Model
import PencilKit
import QuartzCore
import Rendering
import Testing

@testable import CanvasFeature

@MainActor
@Suite("Live stroke handoff")
struct LiveStrokeHandoffTests {
    private let viewSize = Size(width: 200, height: 120)

    private struct Subject {
        let handoff: LiveStrokeHandoff
        let canvasView: PKCanvasView
        let renderer: CanvasRenderer
        let layer: CAMetalLayer
    }

    private func makeSubject() throws -> Subject {
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: viewSize, displayScale: 2)
        let converter = PencilKitStrokeConverter(
            factory: Fixtures.factory(),
            canvasID: Fixtures.canvas
        )
        let handoff = LiveStrokeHandoff(
            canvasView: canvasView,
            renderer: renderer,
            converter: converter
        )
        return Subject(handoff: handoff, canvasView: canvasView, renderer: renderer, layer: layer)
    }

    private func renderUntilIdle(_ renderer: CanvasRenderer, _ layer: CAMetalLayer) async throws {
        for _ in 0..<20 where renderer.renderFrame(into: layer, deadline: nil) {}
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test("A presented stroke leaves the live drawing, and its model stroke is reported")
    func removal() async throws {
        let subject = try makeSubject()
        let (handoff, canvasView) = (subject.handoff, subject.canvasView)
        let (renderer, layer) = (subject.renderer, subject.layer)
        var reported: [Stroke] = []
        handoff.onStrokes = { reported += $0 }
        canvasView.drawing = PKDrawing(strokes: [
            Fixtures.pencilKitStroke(Fixtures.wave(), pointSize: 3)
        ])
        handoff.drawingDidChange(camera: Camera(center: .zero, zoom: 1), viewSize: viewSize)
        #expect(reported.count == 1)
        #expect(handoff.liveStrokeCount == 1)
        try await renderUntilIdle(renderer, layer)
        #expect(handoff.liveStrokeCount == 0)
        #expect(renderer.strokeCount == 1)
    }

    @Test("While the pencil draws the next stroke, the removal waits and keeps the live stroke")
    func fastSecondStroke() async throws {
        let subject = try makeSubject()
        let (handoff, canvasView) = (subject.handoff, subject.canvasView)
        let (renderer, layer) = (subject.renderer, subject.layer)
        let first = Fixtures.pencilKitStroke(Fixtures.wave(), pointSize: 3)
        canvasView.drawing = PKDrawing(strokes: [first])
        handoff.drawingDidChange(camera: Camera(center: .zero, zoom: 1), viewSize: viewSize)
        handoff.isToolInUse = true
        try await renderUntilIdle(renderer, layer)
        #expect(handoff.liveStrokeCount == 1)
        var second = Fixtures.pencilKitStroke(Fixtures.wave(count: 12), pointSize: 3)
        second.transform = CGAffineTransform(translationX: 0, y: 20)
        canvasView.drawing = PKDrawing(strokes: [first, second])
        handoff.isToolInUse = false
        #expect(handoff.liveStrokeCount == 1)
        handoff.drawingDidChange(camera: Camera(center: .zero, zoom: 1), viewSize: viewSize)
        try await renderUntilIdle(renderer, layer)
        #expect(handoff.liveStrokeCount == 0)
        #expect(renderer.strokeCount == 2)
    }

    @Test("A full canvas refuses a live stroke and removes it from the live drawing")
    func strokeLimit() throws {
        let subject = try makeSubject()
        var reported = 0
        subject.handoff.onStrokes = { reported += $0.count }
        subject.handoff.remainingCapacity = { 0 }
        subject.canvasView.drawing = PKDrawing(strokes: [
            Fixtures.pencilKitStroke(Fixtures.wave(), pointSize: 3)
        ])
        subject.handoff.drawingDidChange(camera: Camera(center: .zero, zoom: 1), viewSize: viewSize)
        #expect(reported == 0)
        #expect(subject.renderer.strokeCount == 0)
        #expect(subject.handoff.liveStrokeCount == 0)
    }
}
