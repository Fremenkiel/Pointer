import Geometry
import Model
import QuartzCore
import UIKit.UIGestureRecognizerSubclass
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// The heap allocations on the main thread of the gesture handlers of the canvas, through the
/// objects of UIKit (review M9 section 3.4, item 9, m10-plan.md task 3.7). iOS has no public way
/// to make a touch at a place, so the recognizers are test subclasses that report their state,
/// touches, and place, and the pencil observer gets touches and events of UIKit. A frame takes
/// the inbox after each step, as the display link does in the app. The work of UIKit does not
/// count, as the Metal work does not count (D-43), so `AllocationTracer` counts each allocation
/// by its caller.
@MainActor
final class GestureAllocationTests: XCTestCase {
    private static let steps = 40
    /// The wait after a frame, so that the GPU handlers on other threads end before the next
    /// count, as in `EraserSampleAllocationTests`.
    private static let frameSettle: TimeInterval = 0.005

    /// A pan in the state `.changed` that reports a place in the view.
    private final class ChangedPan: UIPanGestureRecognizer {
        override var state: UIGestureRecognizer.State {
            get { .changed }
            set { _ = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { CGPoint(x: 200, y: 150) }
    }

    /// A pinch of two touches in a state that the test sets.
    private final class TwoFingerPinch: UIPinchGestureRecognizer {
        var testState = UIGestureRecognizer.State.began
        override var state: UIGestureRecognizer.State {
            get { testState }
            set { testState = newValue }
        }
        override var numberOfTouches: Int { 2 }
        override func location(in view: UIView?) -> CGPoint { CGPoint(x: 200, y: 150) }
    }

    @MainActor
    private struct Rig {
        let canvas: CanvasViewController
        let renderer: CanvasRenderer
        let layer = CAMetalLayer()

        init() throws {
            renderer = try CanvasRenderer()
            renderer.configure(layer)
            layer.drawableSize = CGSize(width: 800, height: 600)
            renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
            canvas = CanvasViewController(
                dependencies: CanvasDependencies(
                    renderer: renderer,
                    clock: Fixtures.clock(),
                    content: CanvasContent(canvasID: Fixtures.canvas)
                )
            )
            canvas.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
            canvas.view.layoutIfNeeded()
        }

        /// Draws a frame and lets its handlers end.
        func frame() {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: GestureAllocationTests.frameSettle))
        }
    }

    /// The medians of the Pointer and the system allocations of a step, and the callers of the
    /// Pointer allocations of one step with the median count.
    private struct Medians {
        let pointer: Int
        let system: Int
        let callers: [String]
    }

    /// Returns the median main-thread counts of `step` over the steps, after a first step that
    /// can fill the lists.
    private func medianCount(_ rig: Rig, step: (Int) -> Void) throws -> Medians {
        step(0)
        rig.frame()
        var results: [AllocationTracer.Result] = []
        for index in 1...Self.steps {
            results.append(try XCTUnwrap(AllocationTracer.trace { step(index) }))
            rig.frame()
        }
        XCTAssertEqual(results.map(\.unrecorded).max(), 0, "Each allocation has its caller")
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let pointer = median(results.map(\.pointer))
        return Medians(
            pointer: pointer,
            system: median(results.map(\.system)),
            callers: results.first { $0.pointer == pointer }?.pointerCallers ?? []
        )
    }

    private func check(_ name: String, median: Medians) {
        let counts = "Pointer \(median.pointer), system \(median.system)"
        let line = "allocations of a \(name) step: \(counts)"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual(median.pointer, 0, "\(line); \(median.callers)")
    }

    func testPanStepAllocatesNothing() throws {
        let rig = try Rig()
        let pan = ChangedPan()
        rig.canvas.canvasView.addGestureRecognizer(pan)
        let median = try medianCount(rig) { index in
            pan.setTranslation(CGPoint(x: index.isMultiple(of: 2) ? 3 : -3, y: 1), in: nil)
            rig.canvas.handlePan(pan)
        }
        check("pan", median: median)
    }

    func testPinchStepAllocatesNothing() throws {
        let rig = try Rig()
        let pinch = TwoFingerPinch()
        rig.canvas.canvasView.addGestureRecognizer(pinch)
        pinch.testState = .began
        rig.canvas.handlePinch(pinch)
        pinch.testState = .changed
        let median = try medianCount(rig) { index in
            pinch.scale = 1 + 0.01 * Double(index % 10)
            rig.canvas.handlePinch(pinch)
        }
        pinch.testState = .ended
        rig.canvas.handlePinch(pinch)
        check("pinch", median: median)
    }

    func testPencilMoveAllocatesNothing() throws {
        let rig = try Rig()
        let observer = rig.canvas.pencilObserver
        let touches: Set<UITouch> = [UITouch()]
        let event = UIEvent()
        observer.touchesBegan(touches, with: event)
        let median = try medianCount(rig) { _ in observer.touchesMoved(touches, with: event) }
        observer.touchesEnded(touches, with: event)
        check("pencil move", median: median)
    }
}
