import Metal

/// The completion handler of a command buffer as a Swift `@Sendable` closure (D-132).
///
/// Swift 6 imports the Metal handler type with relaxed concurrency checks (SE-0463). A capture
/// of a non-Sendable value in a handler that Metal takes directly is thus only a warning. Through
/// this method the capture is an error. The lint rule `build_02_metal_handler` bans the direct
/// call.
extension MTLCommandBuffer {
    /// Adds `handler`, which Metal calls on its own thread after the GPU completes the buffer.
    ///
    /// - Precondition: The buffer is not committed yet. Metal checks it.
    func whenCompleted(_ handler: @escaping @Sendable (any MTLCommandBuffer) -> Void) {
        addCompletedHandler(handler)
    }
}
