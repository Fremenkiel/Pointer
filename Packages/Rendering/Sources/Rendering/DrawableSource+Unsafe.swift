import QuartzCore

/// Where a frame gets its drawable: from the display link, or from a layer in the tests.
///
/// Safe as `@unchecked Sendable`: a source exists only during one call of
/// `RenderEngine.renderFrame` on one thread. The frame work uses the drawable in that call and
/// never stores the source, so no other thread can reach the drawable or the layer through it.
/// The type only lets the value pass the lock of `RenderEngine`.
enum DrawableSource: @unchecked Sendable {
    /// The drawable that a `CAMetalDisplayLink` update gave.
    case drawable(any CAMetalDrawable)
    /// A layer whose `nextDrawable()` gives the drawable.
    case layer(CAMetalLayer)

    /// Returns the drawable of the frame, or `nil` if the layer has none.
    func next() -> (any CAMetalDrawable)? {
        switch self {
        case .drawable(let drawable):
            return drawable
        case .layer(let layer):
            assert(layer.device != nil, "The layer has no Metal device")
            return layer.nextDrawable()
        }
    }
}
