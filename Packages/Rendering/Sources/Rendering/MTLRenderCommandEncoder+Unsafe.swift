import Metal

extension MTLRenderCommandEncoder {
    /// Passes a small value to the vertex stage, copied into the command buffer.
    ///
    /// - Precondition: The value fits the 4 KB limit of `setVertexBytes`.
    func setVertexValue<Value>(_ value: Value, index: Int) {
        precondition(MemoryLayout<Value>.size <= 4096, "Value is too large for setVertexBytes")
        precondition(index >= 0, "Buffer index \(index) is invalid")
        var copy = value
        // Safe: Metal copies the bytes during the call, and the value lives until the call ends.
        withUnsafeBytes(of: &copy) { bytes in
            guard let base = bytes.baseAddress else { return }
            setVertexBytes(base, length: bytes.count, index: index)
        }
    }

    /// Passes a small value to the fragment stage, copied into the command buffer.
    ///
    /// - Precondition: The value fits the 4 KB limit of `setFragmentBytes`.
    func setFragmentValue<Value>(_ value: Value, index: Int) {
        precondition(MemoryLayout<Value>.size <= 4096, "Value is too large for setFragmentBytes")
        precondition(index >= 0, "Buffer index \(index) is invalid")
        var copy = value
        // Safe: Metal copies the bytes during the call, and the value lives until the call ends.
        withUnsafeBytes(of: &copy) { bytes in
            guard let base = bytes.baseAddress else { return }
            setFragmentBytes(base, length: bytes.count, index: index)
        }
    }
}
