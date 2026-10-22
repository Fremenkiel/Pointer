import Foundation
import Geometry
import Model

/// A pinch-out exit of a child canvas below the minimum zoom (CARD-05, D-109): the child shrinks
/// into its card frame over the frozen image of the parent.
public struct PinchExit: Sendable, Equatable {
    /// The card frame in the parent canvas, or `nil` if the app does not know it, for example
    /// after a launch into the child. The card then shrinks toward the screen center.
    public let card: Rect?
    /// The parent camera at which the card covers the screen: the start of the exit.
    public let cover: Camera
    /// The parent camera of CARD-04: the end of the exit.
    public let leave: Camera
    /// The progress from 0 to 1.
    public var progress: Double

    /// Makes an exit at progress 0.
    public init(card: Rect?, cover: Camera, leave: Camera) {
        self.card = card
        self.cover = cover
        self.leave = leave
        progress = 0
    }

    /// The progress of an exit at the shown `zoom` of the child: 0 at `minimumZoom` and above,
    /// 1 at `exitZoom` and below (D-104, D-109). The main thread and the render thread use it for
    /// the same value (D-121).
    ///
    /// - Precondition: The zooms are positive.
    public static func progress(zoom: Double, minimumZoom: Double, exitZoom: Double) -> Double {
        precondition(zoom > 0 && minimumZoom > 0 && exitZoom > 0, "Zooms are positive")
        let span = minimumZoom - exitZoom
        guard zoom < minimumZoom, span > 0 else { return 0 }
        return min(max((minimumZoom - zoom) / span, 0), 1)
    }

    /// The smallest size of a card without a known frame, as a part of the screen.
    static let unknownCardScale = 0.25

    /// The parent camera at the progress: the zoom on a log scale, and the center so that the
    /// fixed point of the zoom stays in place, as the flight of an open does (D-98).
    var parentCamera: Camera {
        let progress = min(max(progress, 0), 1)
        let zoom = cover.zoom * pow(leave.zoom / cover.zoom, progress)
        let share =
            cover.zoom == leave.zoom
            ? progress : (1 / cover.zoom - 1 / zoom) / (1 / cover.zoom - 1 / leave.zoom)
        return Camera(center: cover.center + (leave.center - cover.center) * share, zoom: zoom)
    }
}
