import Geometry
import Model
import Rendering
import UIKit
import XCTest
import os

@testable import CanvasFeature

/// The result of one open of a canvas on the screen.
struct OpenMeasurement {
    /// The time of the load from the library, in milliseconds.
    let loadMilliseconds: Double
    /// The time from the start of the load to the end of the first frame that holds all
    /// strokes, in milliseconds.
    let totalMilliseconds: Double
    /// The memory growth from the start of the load to the end of that frame, in MB.
    let heldMegabytes: Double
    /// The largest memory growth during the open, in MB.
    let peakMegabytes: Double
}

/// The memory of an open and a leave between two D-56 canvases, in MB above the steady memory
/// before the parent opened.
struct TransitionMeasurement {
    /// The parent after its first frame.
    let parentHeldMegabytes: Double
    /// The largest growth from the start of the open to the close of the parent.
    let openPeakMegabytes: Double
    /// The growth after the parent closed, with the child shown.
    let heldAfterOpenMegabytes: Double
    /// The largest growth from the load of the parent to the close of the child.
    let leavePeakMegabytes: Double
    /// `true` if the closed parent screen went away, so nothing keeps its content.
    let isParentFreed: Bool
}

/// The lowest free memory of the process since a start.
struct MemoryWatch {
    let base: Int
    private var lowest: Int

    init(base: Int) {
        self.base = base
        lowest = base
    }

    /// Notes the free memory now.
    mutating func look() {
        lowest = min(lowest, os_proc_available_memory())
    }

    /// Starts a new peak from the free memory now.
    mutating func resetLowest() {
        lowest = os_proc_available_memory()
    }

    /// The growth of the memory now over the base, in bytes.
    func held() -> Int { max(0, base - os_proc_available_memory()) }

    /// The largest growth over the base since the last reset, in bytes.
    mutating func peak() -> Int {
        look()
        return max(0, base - lowest)
    }
}

/// The open did not reach a frame with all strokes in time.
struct OpenTimedOut: Error {}

/// Opens a canvas on the screen of the device as the app does at a workspace switch: the load
/// from the library, the canvas screen in the window, and the render thread up to the first
/// frame that holds all strokes (architecture.md section 12).
@MainActor
enum OnScreenCanvas {
    /// The wait between two looks at the renderer.
    private static let pollInterval = Duration.milliseconds(1)
    /// The longest open before the test fails. The budget is 300 ms.
    private static let timeout = Duration.seconds(5)
    /// The wait after a close, so that the render thread of the closed canvas stops.
    private static let settleTime = Duration.milliseconds(500)
    private static let bytesPerMegabyte = 1_048_576.0

    /// Returns the root view controller of the test host window.
    ///
    /// - Throws: An error if the host has no window.
    static func host() throws -> UIViewController {
        // Only UIApplication reaches the window of the host app. The product owner allowed
        // this one use in the open and memory tests on 2026-10-19 (D-62).
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
        return try XCTUnwrap(window?.rootViewController, "The test host has no window")
    }

    /// Opens the canvas of `library` in `host`, measures the open, and closes the canvas.
    ///
    /// - Throws: An error of the load or the renderer, or `OpenTimedOut`.
    static func open(
        _ library: D56Library,
        in host: UIViewController
    ) async throws -> OpenMeasurement {
        let clock = ContinuousClock()
        let restoreHost = clear(host)
        defer { restoreHost() }
        try await waitForSteadyMemory()
        let available = os_proc_available_memory()
        var lowest = available
        let start = clock.now
        let content = try await library.repository.content(of: library.canvas)
        let loaded = clock.now
        let renderer = try CanvasRenderer()
        var dependencies = CanvasDependencies(
            renderer: renderer,
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.repository = library.repository
        let canvas = CanvasViewController(dependencies: dependencies)
        show(canvas, in: host)
        let deadline = start.advanced(by: timeout)
        while renderer.needsMoreFrames || renderer.strokeCount < content.strokes.count {
            guard clock.now < deadline else { throw OpenTimedOut() }
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: pollInterval)
        }
        let end = clock.now
        let held = os_proc_available_memory()
        // The layouts of the text and the card titles run after the first frame (D-92). They end
        // before the close, so that no work of this open runs into the next (m6-plan.md 3.7).
        while renderer.isLoadingText || renderer.isLoadingCards {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: pollInterval)
        }
        close(canvas)
        try await Task.sleep(for: settleTime)
        return OpenMeasurement(
            loadMilliseconds: start.duration(to: loaded) / .milliseconds(1),
            totalMilliseconds: start.duration(to: end) / .milliseconds(1),
            heldMegabytes: megabytes(available - min(available, held)),
            peakMegabytes: megabytes(available - min(lowest, held))
        )
    }

    /// The memory of an open from the D-56 canvas into a D-56 child and of the leave back, from
    /// steady memory before the parent opens (m6-plan.md task 3.6, D-110). The child loads the
    /// same canvas a second time: a second content and a second renderer, as a real child has.
    ///
    /// - Throws: An error of the load or the renderer, or `OpenTimedOut`.
    static func transition(
        _ library: D56Library,
        in host: UIViewController
    ) async throws -> TransitionMeasurement {
        let restoreHost = clear(host)
        defer { restoreHost() }
        try await waitForSteadyMemory()
        var watch = MemoryWatch(base: os_proc_available_memory())
        // The open runs in its own function, so no local value keeps the closed parent alive,
        // as in the app, where the container drops the old screen.
        let opened = try await openChild(library, in: host, watch: &watch)
        try await Task.sleep(for: settleTime)
        let openPeak = watch.peak()
        let afterOpen = watch.held()
        watch.resetLowest()
        let back = try await showCanvas(library, in: host, below: opened.child, watch: &watch)
        back.renderer.camera = Camera(center: .zero, zoom: Limits.standardZoom)
        back.renderer.beginLeave(into: opened.card)
        try await waitForFrames(back.renderer, watch: &watch)
        close(opened.child)
        try await Task.sleep(for: settleTime)
        let leavePeak = watch.peak()
        close(back)
        try await Task.sleep(for: settleTime)
        return TransitionMeasurement(
            parentHeldMegabytes: megabytes(opened.parentHeld),
            openPeakMegabytes: megabytes(openPeak),
            heldAfterOpenMegabytes: megabytes(afterOpen),
            leavePeakMegabytes: megabytes(leavePeak),
            isParentFreed: opened.parent == nil
        )
    }

    /// The child screen after an open, and a weak reference to the closed parent.
    private struct Opened {
        let child: CanvasViewController
        let card: CardID
        let parentHeld: Int
        weak var parent: CanvasViewController?
    }

    /// Shows the parent, opens its first card into a child, and closes the parent.
    private static func openChild(
        _ library: D56Library,
        in host: UIViewController,
        watch: inout MemoryWatch
    ) async throws -> Opened {
        let parent = try await showCanvas(library, in: host, watch: &watch)
        let parentHeld = watch.held()
        guard let card = parent.content.cards.values.first?.id else { throw OpenTimedOut() }
        parent.renderer.beginOpen(of: card)
        try await waitForFrames(parent.renderer, watch: &watch)
        watch.resetLowest()
        let child = try await showCanvas(library, in: host, watch: &watch)
        close(parent)
        return Opened(child: child, card: card, parentHeld: parentHeld, parent: parent)
    }

    /// Loads the canvas of `library`, shows it on top or below `other`, and waits for its first
    /// frame with all strokes and for its text and card loads.
    private static func showCanvas(
        _ library: D56Library,
        in host: UIViewController,
        below other: CanvasViewController? = nil,
        watch: inout MemoryWatch
    ) async throws -> CanvasViewController {
        let content = try await library.repository.content(of: library.canvas)
        let renderer = try CanvasRenderer()
        var dependencies = CanvasDependencies(
            renderer: renderer,
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.repository = library.repository
        let canvas = CanvasViewController(dependencies: dependencies)
        show(canvas, in: host)
        if let other { host.view.bringSubviewToFront(other.view) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while isWorking(renderer, strokes: content.strokes.count) {
            guard clock.now < deadline else { throw OpenTimedOut() }
            watch.look()
            try await Task.sleep(for: pollInterval)
        }
        return canvas
    }

    /// `true` while the renderer has frames to draw, strokes to take, or layouts to make.
    private static func isWorking(_ renderer: CanvasRenderer, strokes: Int) -> Bool {
        renderer.needsMoreFrames || renderer.strokeCount < strokes || renderer.isLoadingText
            || renderer.isLoadingCards
    }

    /// Waits until the renderer drew the frames of its last change.
    private static func waitForFrames(
        _ renderer: CanvasRenderer,
        watch: inout MemoryWatch
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        // The change wakes the frame loop on the next display frame.
        try await Task.sleep(for: .milliseconds(50))
        while renderer.needsMoreFrames {
            guard clock.now < deadline else { throw OpenTimedOut() }
            watch.look()
            try await Task.sleep(for: pollInterval)
        }
        watch.look()
    }

    /// The time without a change of the free memory that counts as steady.
    private static let steadyTime = Duration.milliseconds(1_500)
    /// The longest wait for steady memory.
    private static let steadyTimeout = Duration.seconds(10)
    /// The change of the free memory that counts as a change: one page cluster of 1 MB.
    private static let steadyTolerance = 1_048_576

    /// Waits until the free memory of the process stays the same for `steadyTime`, so that the
    /// drawables of a closed canvas are gone before a measure starts (D-93).
    ///
    /// - Throws: `OpenTimedOut` if the memory does not settle in `steadyTimeout`.
    static func waitForSteadyMemory() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: steadyTimeout)
        var reference = os_proc_available_memory()
        var since = clock.now
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let now = os_proc_available_memory()
            if abs(now - reference) > steadyTolerance {
                reference = now
                since = clock.now
            } else if since.duration(to: clock.now) >= steadyTime {
                return
            }
        }
        throw OpenTimedOut()
    }

    /// Adds the canvas as `AppViewController.show(_:)` does.
    static func show(_ canvas: CanvasViewController, in host: UIViewController) {
        host.addChild(canvas)
        canvas.view.frame = host.view.bounds
        host.view.addSubview(canvas.view)
        canvas.didMove(toParent: host)
        canvas.view.layoutIfNeeded()
    }

    /// Removes the canvas as `AppViewController.show(_:)` removes the old one.
    static func close(_ canvas: CanvasViewController) {
        canvas.willMove(toParent: nil)
        canvas.view.removeFromSuperview()
        canvas.removeFromParent()
    }

    /// Takes the views of `host` out of the window. The test host shows a canvas of its own in
    /// the same process, and its drawables come and go with its frames, by 48 MB (D-93).
    ///
    /// - Returns: The step that closes each canvas that the measure left on `host`, for example
    ///   after a timeout, and puts the views of the host back.
    private static func clear(_ host: UIViewController) -> @MainActor () -> Void {
        let views = host.view.subviews
        let children = host.children
        views.forEach { $0.removeFromSuperview() }
        return {
            for child in host.children where !children.contains(child) {
                guard let canvas = child as? CanvasViewController else { continue }
                close(canvas)
            }
            views.forEach { host.view.addSubview($0) }
        }
    }

    private static func megabytes(_ bytes: Int) -> Double {
        Double(bytes) / bytesPerMegabyte
    }
}
