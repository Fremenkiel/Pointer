import Model
import Rendering

/// The dependencies of the canvas screen. `PointerApp` makes them (ARCH-05).
public struct CanvasDependencies {
    /// The canvas to show.
    public let canvasID: CanvasID
    /// The renderer of the canvas.
    public let renderer: CanvasRenderer
    /// The factory of new strokes, with the ID source and the clock.
    public let strokeFactory: StrokeFactory
    /// The strokes of the canvas at the start.
    public let initialStrokes: [Stroke]

    /// Makes the dependencies.
    public init(
        canvasID: CanvasID,
        renderer: CanvasRenderer,
        strokeFactory: StrokeFactory,
        initialStrokes: [Stroke] = []
    ) {
        self.canvasID = canvasID
        self.renderer = renderer
        self.strokeFactory = strokeFactory
        self.initialStrokes = initialStrokes
    }
}
