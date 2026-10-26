import Metal

extension StoredText {
    /// Copies the records of the current pass into the record buffer of the frame, after the
    /// records of the earlier passes.
    ///
    /// - Returns: The buffer and the byte offset of the records in it, or `nil` if Metal makes
    ///   no buffer.
    func writeRecords() -> (buffer: any MTLBuffer, offset: Int)? {
        precondition(
            recordsUsed + records.count <= Self.recordCapacity,
            "The records fit the buffer of the frame"
        )
        guard let buffer = recordBuffer() else { return nil }
        precondition(
            buffer.length >= (recordsUsed + records.count) * MemoryLayout<GlyphRecord>.stride,
            "The buffer holds the records"
        )
        // Safe: the buffer holds the records of the frame and the pass, as the precondition says.
        let target = buffer.contents()
            .bindMemory(
                to: GlyphRecord.self,
                capacity: buffer.length / MemoryLayout<GlyphRecord>.stride
            )
            .advanced(by: recordsUsed)
        records.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            target.update(from: base, count: source.count)
        }
        return (buffer, recordsUsed * MemoryLayout<GlyphRecord>.stride)
    }
}
