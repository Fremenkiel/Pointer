import Foundation

/// Makes time-ordered UUIDs of version 7 (D-31, RFC 9562 section 5.7).
///
/// The first 48 bits hold the time in milliseconds, so new keys land at the end of a database
/// index. The other bits are random, except the version and the variant.
public enum UUIDVersion7 {
    /// The largest time that fits into 48 bits.
    public static let maxMillis: UInt64 = (1 << 48) - 1

    /// Makes a UUID.
    ///
    /// - Precondition: `millis` fits into 48 bits.
    /// - Returns: A UUID with version 7 and the RFC 9562 variant.
    public static func make(
        millis: UInt64,
        random: inout some RandomNumberGenerator
    ) -> UUID {
        precondition(millis <= maxMillis, "UUID time \(millis) does not fit into 48 bits")
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: millis >> (40 - 8 * UInt64(index)))
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &random)
        }
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
        bytes[8] = 0x80 | (bytes[8] & 0x3F)
        let uuid = UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
        assert(version(of: uuid) == 7, "UUID \(uuid) is not version 7")
        return uuid
    }

    /// Returns the version number of a UUID, from bits 48 to 51.
    public static func version(of uuid: UUID) -> Int {
        Int(uuid.uuid.6 >> 4)
    }

    /// Returns the time in milliseconds of a version 7 UUID.
    public static func millis(of uuid: UUID) -> UInt64 {
        let bytes = uuid.uuid
        let parts = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5]
        return parts.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
