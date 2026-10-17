import Geometry

/// The values of one frame on the render thread.
struct FrameRecord: Sendable {
    /// The time that the frame was for, in `CACurrentMediaTime()` seconds.
    let targetTime: Double
    /// The time that the render thread spent on the frame, in milliseconds.
    let cpuMilliseconds: Double
    /// The identity of the front texture, or `nil` before the first build.
    let front: ObjectIdentifier?
    /// The canvas rectangle of the front texture, or `nil`.
    let frontRect: Rect?
    /// The camera of the frame.
    let camera: Camera
}
