import Foundation
import Model
import Testing

@testable import Persistence

/// The constant facts that the in-place reads and binds and the SQL of the cleanup rely on.
/// They hold at compile time, so the tests stand in for checks in the functions.
@Suite("Layout constants")
struct LayoutConstantTests {
    @Test("A UUID in memory has the 16 bytes of a stored ID")
    func uuidSize() {
        #expect(MemoryLayout<uuid_t>.size == ValueCodec.identifierByteCount)
    }

    @Test("A stored clock value ends with the 16 bytes of the device UUID")
    func clockValueEndsWithDevice() {
        let end = ValueCodec.deviceOffset + ValueCodec.identifierByteCount
        #expect(end == ValueCodec.timestampByteCount)
        #expect(ValueCodec.deviceOffset + MemoryLayout<uuid_t>.size == end)
    }

    @Test("An InkPoint in memory has the 16 bytes of one point in the point BLOB")
    func inkPointStride() {
        #expect(MemoryLayout<InkPoint>.stride == SQLiteStatement.pointByteCount)
    }

    @Test("The tree walk of the tombstone cleanup stops at the depth limit of 32")
    func cleanupDepth() {
        #expect(Limits.maxDepth == 32)
        let walk = "\(LibraryMaintenance.cutoffStatements[0])"
        #expect(walk.contains("doomed.depth < \(Limits.maxDepth)"))
    }
}
