import Foundation

extension PDFExporter {
    /// Returns the bytes of a finished PDF buffer as `Data`, without a copy (D-144).
    ///
    /// The bridge `buffer as Data` copies the whole PDF, up to 226 MB for 200,000 strokes
    /// (the M8 plan section 6.4).
    ///
    /// - Precondition: `buffer` is not empty, and nothing changes it after the call.
    /// - Returns: Data that shares the bytes of `buffer` and keeps it alive.
    static func data(sharing buffer: NSMutableData) -> Data {
        precondition(buffer.length > 0, "A finished PDF buffer is not empty")
        let owner = BufferOwner(buffer: buffer)
        // Safe: `owner` keeps the buffer alive until the deallocator runs, and the caller never
        // changes the buffer again, so the bytes stay valid and fixed for the life of the Data.
        let data = Data(
            bytesNoCopy: buffer.mutableBytes,
            count: buffer.length,
            deallocator: .custom { _, _ in owner.release() }
        )
        return data
    }
}

/// Holds a finished PDF buffer for the deallocator of its `Data`.
///
/// Safe as `@unchecked Sendable`: the buffer never changes after the export, and only the one
/// deallocator call reads the property.
private final class BufferOwner: @unchecked Sendable {
    private var buffer: NSMutableData?

    /// Makes the owner of a finished buffer.
    init(buffer: NSMutableData) {
        self.buffer = buffer
    }

    /// Lets the buffer go.
    func release() {
        buffer = nil
    }
}
