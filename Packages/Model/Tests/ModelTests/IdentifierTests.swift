import Foundation
import Testing

@testable import Model

@Suite("IDs and UUID version 7")
struct IdentifierTests {
    @Test("A version 7 UUID holds the time and the version and variant bits")
    func layout() {
        var random = SeededRandom(state: 1)
        let uuid = UUIDVersion7.make(millis: 0x0123_4567_89AB, random: &random)
        #expect(UUIDVersion7.version(of: uuid) == 7)
        #expect(UUIDVersion7.millis(of: uuid) == 0x0123_4567_89AB)
        #expect(uuid.uuid.8 & 0xC0 == 0x80)
    }

    @Test("UUIDs of later times sort later")
    func order() {
        var random = SeededRandom(state: 1)
        let early = StrokeID(rawValue: UUIDVersion7.make(millis: 1000, random: &random))
        let late = StrokeID(rawValue: UUIDVersion7.make(millis: 1001, random: &random))
        #expect(early < late)
    }

    @Test("The largest 48-bit time is allowed", arguments: [0, UUIDVersion7.maxMillis])
    func edges(millis: UInt64) {
        var random = SeededRandom(state: 3)
        #expect(
            UUIDVersion7.millis(of: UUIDVersion7.make(millis: millis, random: &random)) == millis
        )
    }

    @Test("The factory makes different IDs with the clock time")
    func factory() {
        var factory = IdentifierFactory(
            wallClock: FixedWallClock(millis: 42),
            random: SeededRandom(state: 9)
        )
        let first = factory.make(StrokeID.self)
        let second: CanvasID = factory.make()
        #expect(first.rawValue != second.rawValue)
        #expect(UUIDVersion7.millis(of: first.rawValue) == 42)
    }

    @Test("A time beyond 48 bits uses the largest time")
    func factoryClamp() {
        var factory = IdentifierFactory(
            wallClock: FixedWallClock(millis: .max),
            random: SeededRandom(state: 9)
        )
        #expect(
            UUIDVersion7.millis(of: factory.make(DeviceID.self).rawValue) == UUIDVersion7.maxMillis
        )
    }

    @Test("The description is the lowercase UUID")
    func description() {
        let id = Fixtures.canvas
        #expect(id.description == id.rawValue.uuidString.lowercased())
    }

    @Test("The system clock gives a time after 2020")
    func systemClock() {
        #expect(SystemWallClock().nowMillis() > 1_577_836_800_000)
    }
}
