import Metal
import Synchronization

/// The one set of pipelines per GPU, which all renderers share (review M9 section 3.3, item 3,
/// m10-plan.md task 3.3). Each renderer keeps a command queue of its own.
extension InkResources {
    /// Carries the shared resources out of the lock of the cache.
    ///
    /// Safe: `InkResources` holds only constants, and its Metal objects are the device, a
    /// command queue, pipeline states, and one placeholder texture that no pass writes. Apple
    /// documents the device, the queue, and pipeline states as safe to use from any thread
    /// (<https://developer.apple.com/documentation/metal/mtlcommandqueue>). The box never leaves
    /// this file.
    private struct SharedBox: @unchecked Sendable {
        let resources: InkResources
    }

    /// The resources of the last device, or `nil` before the first renderer.
    private static let cache = Mutex<SharedBox?>(nil)

    /// Returns resources on `device` with the shared pipelines and a new command queue. The
    /// first call compiles the pipelines, and later calls on the same device reuse them. Each
    /// renderer compiled its own before: 2.1 ms warm on the Mac for the first set.
    ///
    /// - Throws: `RenderingError` if the queue, the shader library, or a pipeline fails. A later
    ///   call tries again.
    static func shared(device: any MTLDevice) throws(RenderingError) -> InkResources {
        let box = try cache.withLock { cached throws(RenderingError) -> SharedBox in
            if let cached, cached.resources.device === device { return cached }
            let made = SharedBox(resources: try InkResources(device: device))
            cached = made
            return made
        }
        assert(box.resources.device === device, "The shared pipelines belong to the device")
        return try InkResources(sharingPipelinesOf: box.resources)
    }
}
