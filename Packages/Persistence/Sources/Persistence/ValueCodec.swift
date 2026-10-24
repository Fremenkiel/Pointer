import Foundation
import Model

/// The stored forms of clock values and IDs (storage.md section 3.2).
enum ValueCodec {
    /// The bytes of a clock value: 8 for the wall time, 4 for the counter, 16 for the device.
    static let timestampByteCount = 28
    /// The bytes of an ID: the 16 bytes of its UUID.
    static let identifierByteCount = 16
    /// The bytes of the wall time at the start of a clock value.
    static let wallByteCount = 8
    private static let counterByteCount = 4
    /// The offset of the device UUID in a clock value.
    static let deviceOffset = wallByteCount + counterByteCount
    private static let bitsPerByte = 8
    private static let hexRadix = 16
    private static let hexDigitsPerByte = 2

    /// Returns the 28-byte big-endian form of `timestamp`. The byte order equals the clock order.
    ///
    /// - Precondition: The wall time fits into 48 bits, as each value of `HybridClock` does.
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
        // A larger time stops the clock at its first value, because it passes 48 bits (D-170).
        guard wall <= UUIDVersion7.maxMillis else {
            throw .corruptValue(reason: "clock time \(wall) past 48 bits")
        }
        let counter = UInt32(truncatingIfNeeded: bigEndian(bytes[wallByteCount..<counterEnd]))
        let device = DeviceID(rawValue: try uuid(Data(bytes[counterEnd...])))
        return HybridTimestamp(wallMillis: wall, counter: counter, device: device)
    }

    /// Returns the clock value as 56 lowercase hex digits, the form of the `library` rows (D-58).
    static func hex(_ timestamp: HybridTimestamp) -> String {
        let digits = data(timestamp).map { byte in
            String(byte, radix: hexRadix).leftPadded(to: hexDigitsPerByte)
        }
        return digits.joined()
    }

    /// Returns the clock value of 56 lowercase hex digits.
    ///
    /// - Throws: `PersistenceError.corruptValue` for another length or a character that is not a
    ///   lowercase hex digit.
    static func timestamp(hex: String) throws(PersistenceError) -> HybridTimestamp {
        let characters = Array(hex)
        guard characters.count == timestampByteCount * hexDigitsPerByte, hex == hex.lowercased()
        else {
            throw .corruptValue(reason: "hex clock value of \(characters.count) characters")
        }
        var data = Data(capacity: timestampByteCount)
        for start in stride(from: 0, to: characters.count, by: hexDigitsPerByte) {
            let pair = String(characters[start..<start + hexDigitsPerByte])
            guard let byte = UInt8(pair, radix: hexRadix) else {
                throw .corruptValue(reason: "hex clock value has a character that is not hex")
            }
            data.append(byte)
        }
        return try timestamp(data)
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

extension String {
    /// Returns the string with leading zeros up to `length` characters.
    fileprivate func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
