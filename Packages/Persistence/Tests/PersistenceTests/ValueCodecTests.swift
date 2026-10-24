import Foundation
import Model
import Testing

@testable import Persistence

@Suite("Clock value and ID codecs")
struct ValueCodecTests {
    @Test(
        "A clock value goes to 28 bytes and back unchanged",
        arguments: [
            HybridTimestamp(wallMillis: 0, counter: 0, device: Values.device),
            Values.early,
            HybridTimestamp(
                wallMillis: UUIDVersion7.maxMillis,
                counter: .max,
                device: Values.device
            ),
        ]
    )
    func timestampRoundTrip(timestamp: HybridTimestamp) throws {
        let data = ValueCodec.data(timestamp)
        #expect(data.count == ValueCodec.timestampByteCount)
        #expect(try ValueCodec.timestamp(data) == timestamp)
    }

    @Test("The 28 bytes are big-endian wall time, counter, and device")
    func timestampLayout() {
        let timestamp = HybridTimestamp(
            wallMillis: 0x0000_0304_0506_0708,
            counter: 0x0A0B_0C0D,
            device: Values.device
        )
        let expected = Data(
            [0, 0, 3, 4, 5, 6, 7, 8, 0x0A, 0x0B, 0x0C, 0x0D, 1] + Array(repeating: 0, count: 15)
        )
        #expect(ValueCodec.data(timestamp) == expected)
    }

    @Test("The byte order of the stored form equals the clock order")
    func timestampOrder() {
        let other = DeviceID(rawValue: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        let values = [
            HybridTimestamp(wallMillis: 1, counter: 0, device: Values.device),
            HybridTimestamp(wallMillis: 1, counter: 1, device: Values.device),
            HybridTimestamp(wallMillis: 1, counter: 1, device: other),
            HybridTimestamp(wallMillis: 256, counter: 0, device: Values.device),
        ]
        let stored = values.map(ValueCodec.data)
        for index in 1..<values.count {
            #expect(values[index - 1] < values[index])
            #expect(stored[index - 1].lexicographicallyPrecedes(stored[index]))
        }
    }

    @Test("A clock value of the wrong length throws", arguments: [0, 27, 29])
    func timestampLength(count: Int) {
        #expect(throws: PersistenceError.corruptValue(reason: "clock value of \(count) bytes")) {
            try ValueCodec.timestamp(Data(count: count))
        }
    }

    @Test(
        "A clock time past 48 bits throws, because the clock cannot continue it (D-170)",
        arguments: [UUIDVersion7.maxMillis + 1, .max]
    )
    func timestampPastClockBound(wall: UInt64) {
        // The encoder makes no such value, so the test writes the big-endian bytes itself.
        let wallBytes = (0..<8).reversed().map { UInt8(truncatingIfNeeded: wall >> ($0 * 8)) }
        let data = Data(wallBytes + [0, 0, 0, 0]) + ValueCodec.data(Values.device)
        #expect(throws: PersistenceError.corruptValue(reason: "clock time \(wall) past 48 bits")) {
            try ValueCodec.timestamp(data)
        }
    }

    @Test("An ID goes to its 16 UUID bytes and back unchanged")
    func identifierRoundTrip() throws {
        let id: CardID = Values.id(9)
        let data = ValueCodec.data(id)
        #expect(data == Data([3, 9] + Array(repeating: 0, count: 14)))
        #expect(try ValueCodec.identifier(data) == id)
    }

    @Test("An ID of the wrong length throws", arguments: [0, 15, 17])
    func identifierLength(count: Int) {
        #expect(throws: PersistenceError.corruptValue(reason: "ID of \(count) bytes")) {
            try ValueCodec.identifier(Data(count: count), as: StrokeID.self)
        }
    }

    @Test("A clock value goes to 56 lowercase hex digits and back unchanged (D-58)")
    func hexRoundTrip() throws {
        let hex = ValueCodec.hex(Values.early)
        #expect(hex == "0000018bcfe56800000000000100000000000000000000000000000000".prefix(56))
        #expect(hex.count == 56)
        #expect(try ValueCodec.timestamp(hex: hex) == Values.early)
    }

    @Test(
        "A hex clock value with a wrong length, capitals, or a non-hex character throws",
        arguments: [
            String(repeating: "0", count: 55), String(repeating: "A", count: 56),
            String(repeating: "g", count: 56),
        ]
    )
    func badHex(hex: String) {
        #expect(throws: PersistenceError.self) { try ValueCodec.timestamp(hex: hex) }
    }
}
