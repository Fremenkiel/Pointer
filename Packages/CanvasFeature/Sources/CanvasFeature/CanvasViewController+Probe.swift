/// The state of a canvas that the UI tests read through accessibility values (D-178).
public struct CanvasProbe: Equatable, Sendable {
    /// True while the renderer loads text, cards, or previews (task 2.1 of the M10 plan).
    public let isLoading: Bool
    /// The strokes of the canvas, without the live stroke.
    public let strokeCount: Int
    /// The cards of the canvas, without a pending card (D-117).
    public let cardCount: Int
    /// The level of the canvas in the card tree. The root canvas has level 0.
    public let level: Int
    /// The center of the shown camera in canvas points, rounded to whole points.
    public let cameraCenter: String
}

extension CanvasViewController {
    /// The state that the UI tests read (D-178).
    public var probe: CanvasProbe {
        CanvasProbe(
            isLoading: renderer.isLoading,
            strokeCount: content.strokes.count,
            cardCount: content.cards.count,
            level: level,
            cameraCenter: "\(Int(camera.center.x.rounded())),\(Int(camera.center.y.rounded()))"
        )
    }
}
