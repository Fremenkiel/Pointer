import SQLite3
import struct Foundation.Data

/// The SQLite wrapper can hold C pointers (SAFE-09).
struct SQLiteStatement {
    /// Safe: SQLite owns the handle until finalize.
    let handle: OpaquePointer
}
