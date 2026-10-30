import Geometry
import Testing

@testable import Model

/// The clear of a canvas: one step that removes all strokes, text boxes, and cards (TOOL-10,
/// D-200, TEST-09).
@Suite("Clear canvas")
struct ClearCanvasTests {
    /// Content with three strokes, two text boxes, and two cards.
    private static func rig() throws -> CommandRig {
        var rig = CommandRig()
        _ = try rig.load(3)
        try rig.content.add(RecordTests.textBox(id: Fixtures.id(20), text: "alpha"))
        try rig.content.add(RecordTests.textBox(id: Fixtures.id(21), text: "beta"))
        try rig.content.add(RecordTests.card(id: Fixtures.id(30), title: "Tree"))
        try rig.content.add(RecordTests.card(id: Fixtures.id(31)))
        return rig
    }

    /// Makes sure that an erase record is a tombstone exactly when its stroke is live.
    private static func expectRecordInvariant(_ content: CanvasContent) {
        for (id, record) in content.erased {
            #expect(record.isDeleted == (content.strokes[id] != nil))
        }
    }

    @Test("A clear empties the canvas, the revert gives the content back, and a redo empties it")
    func roundTrip() throws {
        var rig = try Self.rig()
        let start = LiveContent(rig.content)
        let command = ClearCanvas(clearing: rig.content)
        #expect(command.itemCount == 7)
        let cleared = try rig.apply(command)
        #expect(cleared.count == 7)
        #expect(rig.content.strokes.isEmpty)
        #expect(rig.content.nodeCount == 0)
        #expect(cleared.compactMap(\.eraseRecord).map(\.isDeleted) == [false, false, false])
        #expect(cleared.compactMap(\.textBox).map(\.meta.isDeleted) == [true, true])
        #expect(cleared.compactMap(\.card).map(\.meta.isDeleted) == [true, true])
        Self.expectRecordInvariant(rig.content)
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.count == 7)
        #expect(reverted.compactMap(\.eraseRecord).map(\.isDeleted) == [true, true, true])
        #expect(reverted.compactMap(\.textBox).map(\.meta.isDeleted) == [false, false])
        #expect(reverted.compactMap(\.card).map(\.meta.isDeleted) == [false, false])
        Self.expectRecordInvariant(rig.content)
        let redone = try rig.apply(command)
        #expect(redone.count == 7)
        #expect(rig.content.strokes.isEmpty)
        #expect(rig.content.nodeCount == 0)
        Self.expectRecordInvariant(rig.content)
    }

    @Test("A clear of ink alone and of nodes alone works")
    func partialContent() throws {
        var ink = CommandRig()
        _ = try ink.load(2)
        let inkStart = LiveContent(ink.content)
        let inkClear = ClearCanvas(clearing: ink.content)
        #expect(try ink.apply(inkClear).count == 2)
        #expect(ink.content.strokes.isEmpty)
        _ = try ink.revert(inkClear)
        #expect(LiveContent(ink.content) == inkStart)
        var nodes = CommandRig()
        try nodes.content.add(RecordTests.card(id: Fixtures.id(30)))
        let nodeStart = LiveContent(nodes.content)
        let nodeClear = ClearCanvas(clearing: nodes.content)
        #expect(try nodes.apply(nodeClear).count == 1)
        #expect(nodes.content.cards.isEmpty)
        _ = try nodes.revert(nodeClear)
        #expect(LiveContent(nodes.content) == nodeStart)
    }

    @Test("A clear on content that lost an item throws and changes nothing")
    func notLive() throws {
        var rig = try Self.rig()
        let command = ClearCanvas(clearing: rig.content)
        let missingStroke = try #require(command.strokes.last)
        _ = rig.content.remove(missingStroke.id, at: Fixtures.time)
        var before = LiveContent(rig.content)
        #expect(throws: CommandError.strokeNotLive(missingStroke.id)) { try rig.apply(command) }
        #expect(LiveContent(rig.content) == before)
        Self.expectRecordInvariant(rig.content)
        _ = try rig.content.restore(missingStroke, at: Fixtures.time)
        let missingBox = try #require(command.textBoxes.first)
        _ = rig.content.removeTextBox(missingBox.id)
        before = LiveContent(rig.content)
        #expect(throws: CommandError.textBoxNotLive(missingBox.id)) { try rig.apply(command) }
        #expect(LiveContent(rig.content) == before)
        try rig.content.add(missingBox)
        let missingCard = try #require(command.cards.first)
        _ = rig.content.removeCard(missingCard.id)
        before = LiveContent(rig.content)
        #expect(throws: CommandError.cardNotLive(missingCard.id)) { try rig.apply(command) }
        #expect(LiveContent(rig.content) == before)
    }

    @Test("A revert on content that holds an item already throws and changes nothing")
    func alreadyLive() throws {
        var rig = try Self.rig()
        let command = ClearCanvas(clearing: rig.content)
        _ = try rig.apply(command)
        let liveStroke = try #require(command.strokes.last)
        _ = try rig.content.restore(liveStroke, at: Fixtures.time)
        var before = LiveContent(rig.content)
        #expect(throws: CommandError.strokeAlreadyLive(liveStroke.id)) { try rig.revert(command) }
        #expect(LiveContent(rig.content) == before)
        Self.expectRecordInvariant(rig.content)
        _ = rig.content.remove(liveStroke.id, at: Fixtures.time)
        let liveBox = try #require(command.textBoxes.first)
        try rig.content.add(liveBox)
        before = LiveContent(rig.content)
        #expect(throws: CommandError.textBoxAlreadyLive(liveBox.id)) { try rig.revert(command) }
        #expect(LiveContent(rig.content) == before)
        _ = rig.content.removeTextBox(liveBox.id)
        let liveCard = try #require(command.cards.first)
        try rig.content.add(liveCard)
        before = LiveContent(rig.content)
        #expect(throws: CommandError.cardAlreadyLive(liveCard.id)) { try rig.revert(command) }
        #expect(LiveContent(rig.content) == before)
    }

    @Test("A revert on a new load without the session records throws and changes nothing (F-14)")
    func missingRecords() throws {
        var rig = try Self.rig()
        let command = ClearCanvas(clearing: rig.content)
        _ = try rig.apply(command)
        var reloaded = CommandRig()
        let first = try #require(command.strokes.first)
        #expect(throws: CommandError.eraseRecordMissing(first.id)) {
            try reloaded.revert(command)
        }
        #expect(reloaded.content.strokes.isEmpty)
        #expect(reloaded.content.erased.isEmpty)
    }

    @Test("A revert past the node limit throws and changes nothing")
    func nodeLimit() throws {
        var rig = CommandRig()
        try rig.content.add(RecordTests.card(id: Fixtures.id(30)))
        let command = ClearCanvas(clearing: rig.content)
        _ = try rig.apply(command)
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(millis: 1),
            random: SeededRandom(state: 11)
        )
        for _ in 0..<Limits.maxNodesPerCanvas {
            try rig.content.add(RecordTests.textBox(id: identifiers.make(), text: "x"))
        }
        let before = LiveContent(rig.content)
        #expect(throws: CommandError.nodeLimitReached) { try rig.revert(command) }
        #expect(LiveContent(rig.content) == before)
    }

    @Test("A clear holds the bytes of its strokes, texts, and titles, and the IDs of its strokes")
    func heldCost() throws {
        let rig = try Self.rig()
        let command = ClearCanvas(clearing: rig.content)
        let item = HistoryCost.bytes(ofText: nil)
        let strokeBytes = 3 * HistoryCost.bytes(ofStroke: CommandRig.points.count)
        #expect(command.heldByteCount == strokeBytes + 4 * item + 5 + 4 + 4)
        var held: Set<StrokeID> = []
        command.forEachHeldStroke { held.insert($0) }
        #expect(held == Set(rig.content.strokes.keys))
    }

    @Test("A clear of empty content is a programmer error")
    func emptyContent() async {
        await #expect(processExitsWith: .failure) {
            _ = ClearCanvas(clearing: CanvasContent(canvasID: Fixtures.canvas))
        }
    }
}
