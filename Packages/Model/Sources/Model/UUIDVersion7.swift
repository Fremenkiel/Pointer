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
        // Two 64-bit halves instead of an array of 16 bytes, so an ID allocates nothing
        // (docs/m2-fix-plan.md, phase 5). The high half holds the time, the version 7, and 12
        // random bits. The low half holds the variant 0b10 and 62 random bits.
        let high = millis << 16 | 0x7000 | (random.next() & 0x0FFF)
        let low = 0x8000_0000_0000_0000 | (random.next() & 0x3FFF_FFFF_FFFF_FFFF)
        let uuid = UUID(
            uuid: (
                byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
                byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
                byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
                byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
            )
        )
        assert(version(of: uuid) == 7, "UUID \(uuid) is not version 7")
        assert(uuid.uuid.8 >> 6 == 0b10, "UUID \(uuid) has not the RFC 9562 variant")
        return uuid
    }

    /// Returns byte `index` of a value, counted from the most significant byte.
    private static func byte(_ value: UInt64, _ index: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: value >> (56 - 8 * UInt64(index)))
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
