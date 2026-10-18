import Foundation
import Model

/// The stored forms of clock values and IDs (storage.md section 3.2).
enum ValueCodec {
    /// The bytes of a clock value: 8 for the wall time, 4 for the counter, 16 for the device.
    static let timestampByteCount = 28
    /// The bytes of an ID: the 16 bytes of its UUID.
    static let identifierByteCount = 16
    private static let wallByteCount = 8
    private static let counterByteCount = 4
    private static let bitsPerByte = 8

    /// Returns the 28-byte big-endian form of `timestamp`. The byte order equals the clock order.
    static func data(_ timestamp: HybridTimestamp) -> Data {
        var data = Data(capacity: timestampByteCount)
        appendBigEndian(timestamp.wallMillis, byteCount: wallByteCount, to: &data)
        appendBigEndian(UInt64(timestamp.counter), byteCount: counterByteCount, to: &data)
        data.append(Self.data(timestamp.device))
        assert(data.count == timestampByteCount, "Clock value has \(data.count) bytes")
        assert((try? Self.timestamp(data)) == timestamp, "Clock value \(timestamp) does not decode")
        return data
    }

    /// Returns the clock value of a 28-byte stored form.
    ///
    /// - Throws: `PersistenceError.corruptValue` for a length other than 28 bytes.
    static func timestamp(_ data: Data) throws(PersistenceError) -> HybridTimestamp {
        guard data.count == timestampByteCount else {
            throw .corruptValue(reason: "clock value of \(data.count) bytes")
        }
        let bytes = Array(data)
        let counterEnd = wallByteCount + counterByteCount
        let wall = bigEndian(bytes[0..<wallByteCount])
        let counter = UInt32(truncatingIfNeeded: bigEndian(bytes[wallByteCount..<counterEnd]))
        let device = DeviceID(rawValue: try uuid(Data(bytes[counterEnd...])))
        return HybridTimestamp(wallMillis: wall, counter: counter, device: device)
    }

    /// Returns the 16 bytes of the UUID of `identifier`.
    static func data(_ identifier: some EntityIdentifier) -> Data {
        let u = identifier.rawValue.uuid
        return Data([
            u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
        ])
    }

    /// Returns the ID of a 16-byte stored form.
    ///
    /// - Throws: `PersistenceError.corruptValue` for a length other than 16 bytes.
    static func identifier<ID: EntityIdentifier>(
        _ data: Data,
        as type: ID.Type = ID.self
    ) throws(PersistenceError) -> ID {
        ID(rawValue: try uuid(data))
    }

    private static func uuid(_ data: Data) throws(PersistenceError) -> UUID {
        guard data.count == identifierByteCount else {
            throw .corruptValue(reason: "ID of \(data.count) bytes")
        }
        let b = Array(data)
        let uuid = UUID(
            uuid: (
                b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
            )
        )
        assert(Self.data(StrokeID(rawValue: uuid)) == data, "UUID \(uuid) does not encode back")
        return uuid
    }

    private static func appendBigEndian(_ value: UInt64, byteCount: Int, to data: inout Data) {
        precondition(
            byteCount >= 1 && byteCount <= MemoryLayout<UInt64>.size,
            "Cannot write \(byteCount) bytes of UInt64"
        )
        let start = data.count
        for index in (0..<byteCount).reversed() {
            data.append(UInt8(truncatingIfNeeded: value >> (index * bitsPerByte)))
        }
        assert(data.count == start + byteCount, "Wrote \(data.count - start) of \(byteCount) bytes")
    }

    private static func bigEndian(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        assert(
            bytes.count <= MemoryLayout<UInt64>.size,
            "A big-endian value of \(bytes.count) bytes does not fit"
        )
        return bytes.reduce(UInt64(0)) { ($0 << bitsPerByte) | UInt64($1) }
    }
}
