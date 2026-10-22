import Foundation

/// A camera flight in closed form, for the open and the leave of a card (architecture.md 6.2,
/// D-98, D-121). The progress is a critically damped spring of the time since the start, so the
/// main thread and the render thread compute the same camera from the same time.
public struct CameraFlight: Hashable, Sendable {
    /// The time of the open and the leave of a card, in seconds (D-98).
    public static let standardDuration = 0.35
    /// The stiffness of the flight, times its duration: a critically damped spring that reaches
    /// 99.9 % of its way at the end, as (1 + 9.23) e^-9.23 = 0.001.
    static let stiffness = 9.23

    /// The camera at the start.
    public let from: Camera
    /// The camera at the end.
    public let to: Camera
    /// The time of the flight, in seconds.
    public let duration: Double
    /// The start, in seconds, in the time base of `CACurrentMediaTime()`.
    public let start: Double

    /// Makes a flight from `from` to `to` that starts at `start` and takes `duration` seconds.
    ///
    /// - Precondition: `duration` is positive and finite, and `start` is finite.
    public init(from: Camera, to: Camera, duration: Double = standardDuration, start: Double) {
        precondition(duration > 0 && duration.isFinite, "A flight takes time, got \(duration)")
        precondition(start.isFinite, "A flight starts at a finite time, got \(start)")
        self.from = from
        self.to = to
        self.duration = duration
        self.start = start
    }

    /// The time at which the flight is at its target.
    public var end: Double { start + duration }

    /// Returns the progress at `time`, from 0 at the start to 1 at the end and after it.
    ///
    /// - Precondition: `time` is finite.
    public func progress(at time: Double) -> Double {
        precondition(time.isFinite, "A flight time is finite, got \(time)")
        let part = min(max((time - start) / duration, 0), 1)
        let progress = min(Self.reach(at: part) / Self.reach(at: 1), 1)
        assert((0...1).contains(progress), "Progress \(progress) is from 0 to 1")
        return progress
    }

    /// Returns the camera at `time`. The zoom moves on a log scale, and the center moves so that
    /// the fixed point of the zoom stays in place on the screen. At the end, it is exactly `to`.
    ///
    /// - Precondition: `time` is finite.
    public func camera(at time: Double) -> Camera {
        let progress = progress(at: time)
        guard progress < 1 else { return to }
        let zoom = from.zoom * pow(to.zoom / from.zoom, progress)
        assert(zoom > 0 && zoom.isFinite, "The zoom \(zoom) of a flight is positive")
        let share =
            from.zoom == to.zoom
            ? progress : (1 / from.zoom - 1 / zoom) / (1 / from.zoom - 1 / to.zoom)
        return Camera(center: from.center + (to.center - from.center) * share, zoom: zoom)
    }

    /// The way of a critically damped spring at a part from 0 to 1 of the flight.
    private static func reach(at part: Double) -> Double {
        1 - (1 + stiffness * part) * exp(-stiffness * part)
    }
}
