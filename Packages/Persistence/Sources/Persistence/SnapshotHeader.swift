import Foundation

/// The 100 bytes at the start of a SQLite file, checked in Swift before SQLite reads the file
/// (D-162, <https://www.sqlite.org/fileformat.html> section 1.3).
struct SnapshotHeader: Equatable {
    /// The length of the header.
    static let length = 100
    /// "SQLite format 3" and a zero byte.
    private static let magic = Data("SQLite format 3\u{0}".utf8)
    /// The offsets of the fields that the check reads.
    private static let pageSizeOffset = 16
    private static let writeVersionOffset = 18
    private static let readVersionOffset = 19
    private static let userVersionOffset = 60
    /// The value of the version bytes 18 and 19 of a file in rollback mode. WAL mode has 2.
    private static let rollbackVersion: UInt8 = 1
    private static let walVersion: UInt8 = 2

    /// The schema version of the file, `PRAGMA user_version`.
    let userVersion: Int64

    /// Checks the header of a file of `fileSize` bytes.
    ///
    /// - Precondition: `fileSize` is not negative.
    /// - Throws: `PersistenceError.notADatabase` without the magic, `.wrongPageSize` for another
    ///   page size than 4,096, `.walMode` for a file in WAL mode, `.incompleteFile` for a size
    ///   that is not whole pages, `.unknownVersion` for a version below 1, and `.newerSchema`
    ///   for a version above `Schema.currentVersion`.
    init(_ bytes: Data, fileSize: Int) throws(PersistenceError) {
        precondition(fileSize >= 0, "A file size of \(fileSize) bytes")
        let header = Data(bytes.prefix(Self.length))
        guard header.count == Self.length, header.prefix(Self.magic.count) == Self.magic else {
            throw .notADatabase
        }
        let pageSize = Int(Self.bigEndian(header, at: Self.pageSizeOffset, count: 2))
        guard pageSize == Int(SQLiteConnection.pageSize) else {
            // The value 1 stands for 65,536 bytes.
            throw .wrongPageSize(bytes: pageSize == 1 ? 65_536 : pageSize)
        }
        let versions = [header[Self.writeVersionOffset], header[Self.readVersionOffset]]
        guard versions.allSatisfy({ $0 == Self.rollbackVersion }) else {
            throw versions.contains(Self.walVersion) ? .walMode : .notADatabase
        }
        guard fileSize % pageSize == 0 else { throw .incompleteFile(byteCount: fileSize) }
        let raw = UInt32(Self.bigEndian(header, at: Self.userVersionOffset, count: 4))
        userVersion = Int64(Int32(bitPattern: raw))
        guard userVersion >= 1 else { throw .unknownVersion(userVersion) }
        guard userVersion <= Schema.currentVersion else {
            throw .newerSchema(version: userVersion)
        }
    }

    /// Reads `count` bytes at `offset` as one unsigned big-endian number.
    private static func bigEndian(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        precondition(count <= 8, "At most 8 bytes fit, got \(count)")
        precondition(offset + count <= data.count, "The field ends past the header")
        return data[offset..<offset + count].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
