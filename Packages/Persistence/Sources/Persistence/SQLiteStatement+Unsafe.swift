import Foundation
import Model
import SQLite3

/// One compiled SQL statement that the owner binds, steps, and resets for each use.
///
/// It is not `Sendable`. It belongs to the actor that owns its connection. Parameter indexes
/// start at 1, and column indexes start at 0, as in SQLite.
final class SQLiteStatement {
    /// Safe: SQLite reads the value at the bind call and keeps its own copy, so the Swift buffer
    /// can go away after the call. This is the `SQLITE_TRANSIENT` constant of the C header,
    /// which Swift does not import.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Keeps the connection open while the statement exists.
    private let connection: SQLiteConnection
    /// Safe: `sqlite3_prepare_v3` gives the handle, and only `deinit` finalizes it.
    private let handle: OpaquePointer

    /// Wraps a compiled statement of `connection`.
    init(connection: SQLiteConnection, handle: OpaquePointer) {
        self.connection = connection
        self.handle = handle
    }

    deinit {
        // The result repeats the error of the last step, which `step()` already threw.
        sqlite3_finalize(handle)
    }

    /// Binds an integer to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(_ value: Int64, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        try connection.check(sqlite3_bind_int64(handle, index, value), expected: SQLITE_OK)
    }

    /// Binds a floating-point number to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(_ value: Double, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        try connection.check(sqlite3_bind_double(handle, index, value), expected: SQLITE_OK)
    }

    /// Binds UTF-8 text to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.valueTooLarge` above `Int32.max` bytes, and
    ///   `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(_ value: String, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        let byteCount = value.utf8.count
        guard let length = Int32(exactly: byteCount) else {
            throw .valueTooLarge(byteCount: byteCount)
        }
        let code = sqlite3_bind_text(handle, index, value, length, Self.transient)
        try connection.check(code, expected: SQLITE_OK)
    }

    /// Binds bytes to the parameter at `index`. Empty data binds an empty blob, not NULL.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.valueTooLarge` above `Int32.max` bytes, and
    ///   `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(_ value: Data, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        guard let length = Int32(exactly: value.count) else {
            throw .valueTooLarge(byteCount: value.count)
        }
        let code = value.withUnsafeBytes { bytes in
            // Empty data has no base address. A nil pointer would bind NULL.
            guard let base = bytes.baseAddress else {
                return sqlite3_bind_zeroblob(handle, index, 0)
            }
            return sqlite3_bind_blob(handle, index, base, length, Self.transient)
        }
        try connection.check(code, expected: SQLITE_OK)
    }

    /// Binds NULL to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.sqlite` if SQLite refuses the value.
    func bindNull(at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        try connection.check(sqlite3_bind_null(handle, index), expected: SQLITE_OK)
    }

    /// Runs the statement to its next row.
    ///
    /// - Returns: True if a row is ready to read, false if the statement is done.
    /// - Throws: `PersistenceError.sqlite` with the SQLite message if the step fails. The
    ///   statement is then reset, so the owner can use it again.
    func step() throws(PersistenceError) -> Bool {
        let code = sqlite3_step(handle)
        if code == SQLITE_ROW { return true }
        guard code == SQLITE_DONE else {
            let error = PersistenceError.sqlite(
                code: code,
                message: String(cString: sqlite3_errmsg(connection.handle))
            )
            // After a failed step, the reset gives the same code again.
            let repeated = sqlite3_reset(handle)
            assert(repeated == code, "Reset gave \(repeated) after step error \(code)")
            throw error
        }
        return false
    }

    /// Resets the statement and clears its parameters for the next use.
    ///
    /// - Throws: `PersistenceError.sqlite` if the reset fails.
    func reset() throws(PersistenceError) {
        try connection.check(sqlite3_reset(handle), expected: SQLITE_OK)
        try connection.check(sqlite3_clear_bindings(handle), expected: SQLITE_OK)
    }

    /// The number of parameters.
    var parameterCount: Int32 { sqlite3_bind_parameter_count(handle) }

    /// The number of result columns.
    var columnCount: Int32 { sqlite3_column_count(handle) }

    /// The number of rows that the last step changed.
    var changes: Int64 { sqlite3_changes64(connection.handle) }

    /// Returns true if the column at `column` of the current row is NULL.
    ///
    /// - Precondition: `column` is a column of the statement.
    func isNull(at column: Int32) -> Bool {
        checkColumn(column)
        return sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    /// Returns the column at `column` of the current row as an integer.
    ///
    /// - Precondition: `column` is a column of the statement.
    func int64(at column: Int32) -> Int64 {
        checkColumn(column)
        return sqlite3_column_int64(handle, column)
    }

    /// Returns the column at `column` of the current row as a floating-point number.
    ///
    /// - Precondition: `column` is a column of the statement.
    func double(at column: Int32) -> Double {
        checkColumn(column)
        return sqlite3_column_double(handle, column)
    }

    /// Returns the column at `column` of the current row as text.
    ///
    /// - Precondition: `column` is a column of the statement.
    /// - Returns: The text, or `nil` for NULL or bytes that are not valid UTF-8.
    func string(at column: Int32) -> String? {
        checkColumn(column)
        guard let text = sqlite3_column_text(handle, column) else { return nil }
        // The byte count comes after the text call, as the SQLite documentation asks.
        let count = Int(sqlite3_column_bytes(handle, column))
        return String(validating: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
    }

    /// Returns the column at `column` of the current row as bytes, copied in one step.
    ///
    /// - Precondition: `column` is a column of the statement.
    /// - Returns: The bytes, or `nil` for NULL. An empty blob gives empty data.
    func data(at column: Int32) -> Data? {
        checkColumn(column)
        guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
        let bytes = sqlite3_column_blob(handle, column)
        let count = Int(sqlite3_column_bytes(handle, column))
        guard let bytes, count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func checkParameter(_ index: Int32) {
        precondition(
            index >= 1 && index <= sqlite3_bind_parameter_count(handle),
            "Parameter \(index) is not a parameter of the statement"
        )
    }

    private func checkColumn(_ column: Int32) {
        precondition(
            column >= 0 && column < sqlite3_column_count(handle),
            "Column \(column) is not a column of the statement"
        )
    }
}

/// IDs and clock values read and bound in place, without a `Data` and an `Array` per value
/// (P-11 of docs/m4-fix-plan.md). The forms are those of `ValueCodec` (storage.md section 3.2).
extension SQLiteStatement {
    /// Returns the UUID of a 16-byte ID column, or `nil` for NULL.
    ///
    /// - Precondition: `column` is a column of the statement.
    /// - Throws: `PersistenceError.corruptValue` for a length other than 16 bytes.
    func uuid(at column: Int32) throws(PersistenceError) -> UUID? {
        checkColumn(column)
        guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
        let bytes = sqlite3_column_blob(handle, column)
        let count = Int(sqlite3_column_bytes(handle, column))
        guard let bytes, count == ValueCodec.identifierByteCount else {
            throw .corruptValue(reason: "ID of \(count) bytes")
        }
        // Safe: SQLite keeps the blob until the next step, and the length is checked above.
        return UUID(uuid: UnsafeRawPointer(bytes).loadUnaligned(as: uuid_t.self))
    }

    /// Returns the clock value of a 28-byte column, or `nil` for NULL.
    ///
    /// - Precondition: `column` is a column of the statement.
    /// - Throws: `PersistenceError.corruptValue` for a length other than 28 bytes.
    func timestamp(at column: Int32) throws(PersistenceError) -> HybridTimestamp? {
        checkColumn(column)
        guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
        let bytes = sqlite3_column_blob(handle, column)
        let count = Int(sqlite3_column_bytes(handle, column))
        guard let bytes, count == ValueCodec.timestampByteCount else {
            throw .corruptValue(reason: "clock value of \(count) bytes")
        }
        // Safe: SQLite keeps the blob until the next step, and the length is checked above.
        let raw = UnsafeRawPointer(bytes)
        let wall = UInt64(bigEndian: raw.loadUnaligned(as: UInt64.self))
        let counter = UInt32(
            bigEndian: raw.loadUnaligned(fromByteOffset: ValueCodec.wallByteCount, as: UInt32.self)
        )
        let device = raw.loadUnaligned(fromByteOffset: ValueCodec.deviceOffset, as: uuid_t.self)
        return HybridTimestamp(
            wallMillis: wall,
            counter: counter,
            device: DeviceID(rawValue: UUID(uuid: device))
        )
    }

    /// Binds the 16 bytes of a UUID to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(uuid: UUID, at index: Int32) throws(PersistenceError) {
        precondition(
            index >= 1 && index <= sqlite3_bind_parameter_count(handle),
            "Parameter \(index) is not a parameter of the statement"
        )
        // Safe: SQLite copies the bytes (SQLITE_TRANSIENT) before the closure returns.
        let code = withUnsafeBytes(of: uuid.uuid) { bytes in
            sqlite3_bind_blob(
                handle,
                index,
                bytes.baseAddress,
                Int32(ValueCodec.identifierByteCount),
                Self.transient
            )
        }
        try connection.check(code, expected: SQLITE_OK)
    }

    /// Binds the 28-byte big-endian form of a clock value to the parameter at `index`.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(timestamp: HybridTimestamp, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        precondition(
            timestamp.wallMillis <= UUIDVersion7.maxMillis,
            "Clock time \(timestamp.wallMillis) passes 48 bits"
        )
        let count = ValueCodec.timestampByteCount
        // Safe: the buffer lives on the stack for the closure, and SQLite copies the bytes
        // (SQLITE_TRANSIENT) before it returns.
        let code = withUnsafeTemporaryAllocation(byteCount: count, alignment: 1) { buffer in
            buffer.storeBytes(of: timestamp.wallMillis.bigEndian, toByteOffset: 0, as: UInt64.self)
            buffer.storeBytes(
                of: timestamp.counter.bigEndian,
                toByteOffset: ValueCodec.wallByteCount,
                as: UInt32.self
            )
            withUnsafeBytes(of: timestamp.device.rawValue.uuid) { device in
                let target = UnsafeMutableRawBufferPointer(
                    rebasing: buffer[ValueCodec.deviceOffset...]
                )
                target.copyMemory(from: device)
            }
            return sqlite3_bind_blob(
                handle,
                index,
                buffer.baseAddress,
                Int32(count),
                Self.transient
            )
        }
        try connection.check(code, expected: SQLITE_OK)
    }
}

extension SQLiteStatement {
    /// The bytes of one point in the point BLOB (storage.md section 3.4).
    static let pointByteCount = 16

    /// Binds the point BLOB of a stroke to the parameter at `index`.
    ///
    /// The BLOB holds the points without a header, 16 bytes each, little-endian. The layout
    /// equals `InkPoint` in memory, so the bind copies the array once.
    ///
    /// - Precondition: `index` is a parameter of the statement.
    /// - Throws: `PersistenceError.valueTooLarge` above `Int32.max` bytes, and
    ///   `PersistenceError.sqlite` if SQLite refuses the value.
    func bind(_ points: InkPoints, at index: Int32) throws(PersistenceError) {
        checkParameter(index)
        let byteCount = points.count * Self.pointByteCount
        guard let length = Int32(exactly: byteCount) else {
            throw .valueTooLarge(byteCount: byteCount)
        }
        // Safe: the buffer is valid during the call, and SQLite copies it (SQLITE_TRANSIENT).
        let code = points.values.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            sqlite3_bind_blob(handle, index, bytes.baseAddress, length, Self.transient)
        }
        try connection.check(code, expected: SQLITE_OK)
    }

    /// Returns the points of the point BLOB at `column`, copied in one step after the length
    /// check (storage.md section 3.4).
    ///
    /// - Precondition: `column` is a column of the statement.
    /// - Throws: `PersistenceError.corruptValue` if `count` is outside
    ///   `2...Limits.maxPointsPerStroke` or the BLOB does not hold `count` points.
    func inkPoints(at column: Int32, count: Int) throws(PersistenceError) -> [InkPoint] {
        checkColumn(column)
        guard count >= 2, count <= Limits.maxPointsPerStroke else {
            throw .corruptValue(reason: "point count \(count)")
        }
        let bytes = sqlite3_column_blob(handle, column)
        let byteCount = Int(sqlite3_column_bytes(handle, column))
        guard let bytes, byteCount == count * Self.pointByteCount else {
            throw .corruptValue(reason: "point BLOB of \(byteCount) bytes for \(count) points")
        }
        // Safe: SQLite keeps `bytes` valid until the next step, and the copy fills all `count`
        // points of the new array. All Apple platforms are little-endian, as the BLOB.
        return [InkPoint](unsafeUninitializedCapacity: count) { buffer, initialized in
            UnsafeMutableRawBufferPointer(buffer).copyMemory(
                from: UnsafeRawBufferPointer(start: bytes, count: byteCount)
            )
            initialized = count
        }
    }
}
