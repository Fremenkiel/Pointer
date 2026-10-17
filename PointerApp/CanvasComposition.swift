import CanvasFeature
import Model
import Rendering
import UIKit
import os

/// Makes the canvas screen and its dependencies (ARCH-01, ARCH-05).
///
/// M2 has no storage: the canvas starts empty at each launch, and the device ID is new at each
/// launch. M3 loads both from the library.
@MainActor
enum CanvasComposition {
    /// The launch argument that fills the canvas for the performance tests, for example
    /// `-fillStrokes 20000`.
    static let fillStrokesKey = "fillStrokes"
    /// The launch argument that sets the control points per synthetic stroke.
    static let fillPointsKey = "fillPoints"
    /// The launch argument that sets the draw instances per frame of a build, for tuning on a
    /// device (D-28), for example `-instanceBudget 60000`.
    static let instanceBudgetKey = "instanceBudget"
    /// The control points per synthetic stroke without the launch argument.
    static let defaultFillPoints = 300

    /// Returns the canvas screen, or a black screen if the device has no Metal GPU.
    static func makeRootViewController(defaults: UserDefaults) -> UIViewController {
        let wallClock = SystemWallClock()
        var identifiers = IdentifierFactory(
            wallClock: wallClock,
            random: SystemRandomNumberGenerator()
        )
        let device: DeviceID = identifiers.make()
        let canvasID: CanvasID = identifiers.make()
        var factory = StrokeFactory(
            identifiers: identifiers,
            clock: HybridClock(device: device, wallClock: wallClock)
        )
        let renderer: CanvasRenderer
        do {
            var configuration = RendererConfiguration()
            let budget = defaults.integer(forKey: instanceBudgetKey)
            if budget > 0 {
                configuration.instanceBudgetPerFrame = budget
            }
            renderer = try CanvasRenderer(configuration: configuration)
        } catch {
            Logger(subsystem: "dk.saarikivi.pointer", category: "App")
                .fault("The renderer failed: \(String(describing: error))")
            return RootViewController()
        }
        let strokes = fillStrokes(defaults: defaults, canvasID: canvasID, factory: &factory)
        let dependencies = CanvasDependencies(
            canvasID: canvasID,
            renderer: renderer,
            strokeFactory: factory,
            initialStrokes: strokes
        )
        return CanvasViewController(dependencies: dependencies)
    }

    private static func fillStrokes(
        defaults: UserDefaults,
        canvasID: CanvasID,
        factory: inout StrokeFactory
    ) -> [Stroke] {
        let count = min(
            max(defaults.integer(forKey: fillStrokesKey), 0),
            Limits.maxStrokesPerCanvas
        )
        guard count > 0 else { return [] }
        let requestedPoints = defaults.integer(forKey: fillPointsKey)
        let points =
            requestedPoints >= 2
            ? min(requestedPoints, Limits.maxPointsPerStroke) : defaultFillPoints
        return StressContent.makeStrokes(
            count: count,
            pointsPerStroke: points,
            canvasID: canvasID,
            factory: &factory
        )
    }
}
