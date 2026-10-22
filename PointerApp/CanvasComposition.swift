import CanvasFeature
import DesignSystem
import Model
import Rendering
import UIKit

/// The launch arguments of the canvas for the performance tests (ARCH-01).
@MainActor
enum CanvasComposition {
    /// The launch argument that fills the canvas for the performance tests, for example
    /// `-fillStrokes 20000`. The fill content is never saved (D-55).
    static let fillStrokesKey = "fillStrokes"
    /// The launch argument that sets the control points per synthetic stroke.
    static let fillPointsKey = "fillPoints"
    /// The launch argument that sets the draw instances per frame of a build, for tuning on a
    /// device (D-28), for example `-instanceBudget 60000`.
    static let instanceBudgetKey = "instanceBudget"
    /// The control points per synthetic stroke without the launch argument.
    static let defaultFillPoints = 300

    /// Returns the renderer configuration with the instance budget of the launch argument.
    static func rendererConfiguration(_ defaults: UserDefaults) -> RendererConfiguration {
        var configuration = RendererConfiguration()
        configuration.background = DesignSystem.Color.canvasBackgroundSRGB
        configuration.cardBorderCoverage = DesignSystem.Color.cardBorder
        configuration.cardFillCoverage = DesignSystem.Color.cardFill
        let budget = defaults.integer(forKey: instanceBudgetKey)
        if budget > 0 {
            configuration.instanceBudgetPerFrame = budget
        }
        return configuration
    }

    /// Returns the fill strokes of the launch argument, at most `limit`.
    static func fillStrokes(
        defaults: UserDefaults,
        canvasID: CanvasID,
        limit: Int,
        factory: inout StrokeFactory
    ) -> [Stroke] {
        let count = min(max(defaults.integer(forKey: fillStrokesKey), 0), max(limit, 0))
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
