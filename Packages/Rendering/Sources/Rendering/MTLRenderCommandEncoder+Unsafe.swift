import Metal

extension MTLRenderCommandEncoder {
    /// Passes a small value to the vertex stage, copied into the command buffer.
    ///
    /// - Precondition: The value fits the 4 KB limit of `setVertexBytes`.
    func setVertexValue<Value: BitwiseCopyable>(_ value: Value, index: Int) {
        precondition(index >= 0, "Buffer index \(index) is invalid")
        withPaddedBytes(of: value) { base, length in
            setVertexBytes(base, length: length, index: index)
        }
    }

    /// Passes a small value to the fragment stage, copied into the command buffer.
    ///
    /// - Precondition: The value fits the 4 KB limit of `setFragmentBytes`.
    func setFragmentValue<Value: BitwiseCopyable>(_ value: Value, index: Int) {
        precondition(index >= 0, "Buffer index \(index) is invalid")
        withPaddedBytes(of: value) { base, length in
            setFragmentBytes(base, length: length, index: index)
        }
    }

    /// Gives the bytes of `value` with the padding at its end, zeroed. Metal rounds the size of a
    /// struct up to its alignment, as the stride of Swift does, so a struct that ends in a
    /// `float` after a `float2` takes 24 bytes in Metal and 20 bytes as the size in Swift. API
    /// validation refuses the shorter length.
    private func withPaddedBytes<Value: BitwiseCopyable>(
        of value: Value,
        _ body: (UnsafeRawPointer, Int) -> Void
    ) {
        let length = MemoryLayout<Value>.stride
        precondition(length <= 4096, "A value of \(length) bytes is too large for set*Bytes")
        // Safe: the buffer lives on the stack until the call ends, it holds `length` bytes with
        // the alignment of `Value`, and Metal copies the bytes during the call.
        withUnsafeTemporaryAllocation(
            byteCount: length,
            alignment: MemoryLayout<Value>.alignment
        ) { buffer in
            guard let base = buffer.baseAddress else {
                preconditionFailure("A buffer of \(length) bytes has no address")
            }
            base.initializeMemory(as: UInt8.self, repeating: 0, count: length)
            base.storeBytes(of: value, as: Value.self)
            body(UnsafeRawPointer(base), length)
        }
    }
}
