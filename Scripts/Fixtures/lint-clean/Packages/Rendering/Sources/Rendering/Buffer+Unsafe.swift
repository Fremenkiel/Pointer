import Metal

/// Tier B can hold Metal buffer pointers in a +Unsafe file (SAFE-09).
struct Buffer {
    /// Safe: the Metal buffer owns the memory while the frame is in flight.
    let contents: UnsafeMutableRawPointer
    /// The device that made the buffer.
    let device: any MTLDevice
}
