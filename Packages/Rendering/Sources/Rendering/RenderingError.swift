/// The errors of the Rendering package.
public enum RenderingError: Error, Equatable, Sendable {
    /// The device has no Metal GPU.
    case noDevice
    /// A Metal object could not be made. The value names the object.
    case resourceUnavailable(String)
    /// A render pipeline could not be compiled.
    case pipelineFailed(String)
}
