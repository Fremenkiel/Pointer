import Geometry
import Testing

@testable import Model

@Suite("Canvas commands")
struct CommandTests {
    /// Content with loaded strokes, a card, and a text box.
    private static func rig() throws -> (CommandRig, [Stroke]) {
        var rig = CommandRig()
        let loaded = try rig.load(4)
        try rig.content.add(RecordTests.card())
        try rig.content.add(RecordTests.textBox(text: "node"))
        return (rig, loaded)
    }

    @Test("Adding strokes and reverting the add gives back the live content", arguments: [1, 3])
    func addStrokeRoundTrip(count: Int) throws {
        var (rig, _) = try Self.rig()
        let start = LiveContent(rig.content)
        let command = AddStroke(strokes: (0..<count).map { _ in rig.stroke(x: 50) })
        let added = try rig.apply(command)
        #expect(added.compactMap(\.stroke).map(\.id) == command.strokes.map(\.id))
        #expect(LiveContent(rig.content) != start)
        let reverted = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
        #expect(reverted.compactMap(\.eraseRecord).map(\.strokeID) == command.strokes.map(\.id))
    }

    @Test("Erasing strokes and reverting the erase gives back the live content", arguments: [0, 2])
    func eraseRoundTrip(partCount: Int) throws {
        var (rig, loaded) = try Self.rig()
        let start = LiveContent(rig.content)
        let parts = (0..<partCount).map { _ in rig.stroke(x: 70) }
        let command = EraseStrokes(removed: Array(loaded.prefix(2)), parts: parts)
        let erased = try rig.apply(command)
        #expect(erased.compactMap(\.eraseRecord).count == 2)
        #expect(erased.compactMap(\.stroke).map(\.id) == parts.map(\.id))
        #expect(rig.content.strokes.count == loaded.count - 2 + partCount)
        _ = try rig.revert(command)
        #expect(LiveContent(rig.content) == start)
    }

    @Test("After the undo of an erase, each erase record of a live stroke is a tombstone")
    func eraseRecordsAfterRevert() throws {
        var (rig, loaded) = try Self.rig()
        let parts = [rig.stroke(x: 70), rig.stroke(x: 80)]
        let command = EraseStrokes(removed: [loaded[0], loaded[1]], parts: parts)
        _ = try rig.apply(command)
        let rows = try rig.revert(command)
        for stroke in command.removed {
            #expect(rig.content.erased[stroke.id]?.isDeleted == true)
        }
        for part in parts {
            #expect(rig.content.erased[part.id]?.isDeleted == false)
            #expect(rig.content.strokes[part.id] == nil)
        }
        for (id, record) in rig.content.erased {
            #expect(record.isDeleted == (rig.content.strokes[id] != nil))
        }
        #expect(rows.compactMap(\.eraseRecord).count == 4)
        #expect(rows.compactMap(\.stroke).isEmpty)
    }

    @Test("The redo of an add turns the erase records of the undo into tombstones (D-68)")
    func addStrokeRedo() throws {
        var rig = CommandRig()
        let command = AddStroke(strokes: [rig.stroke()])
        let id = command.strokes[0].id
        _ = try rig.apply(command)
        _ = try rig.revert(command)
        let undoRecord = try #require(rig.content.erased[id])
        #expect(!undoRecord.isDeleted)
        let rows = try rig.apply(command)
        let redoRecord = try #require(rows.first?.eraseRecord)
        #expect(redoRecord.isDeleted)
        #expect(redoRecord.erased == undoRecord.erased)
        #expect(redoRecord.modified > undoRecord.modified)
        #expect(rig.content.strokes[id] != nil)
    }

    @Test("The redo of an erase gives the live content of the first erase")
    func eraseRedo() throws {
        var (rig, loaded) = try Self.rig()
        let command = EraseStrokes(removed: [loaded[2]], parts: [rig.stroke(x: 90)])
        _ = try rig.apply(command)
        let erasedContent = LiveContent(rig.content)
        _ = try rig.revert(command)
        let rows = try rig.apply(command)
        #expect(LiveContent(rig.content) == erasedContent)
        #expect(rows.compactMap(\.stroke).isEmpty)
        #expect(rig.content.erased[command.parts[0].id]?.isDeleted == true)
        #expect(rig.content.erased[loaded[2].id]?.isDeleted == false)
    }

    @Test("A command that does not fit the content throws and leaves the content as it was")
    func refusedCommands() throws {
        var (rig, loaded) = try Self.rig()
        let start = LiveContent(rig.content)
        #expect(throws: CommandError.strokeAlreadyLive(loaded[0].id)) {
            try rig.apply(AddStroke(strokes: [rig.stroke(), loaded[0]]))
        }
        let missing = rig.stroke()
        #expect(throws: CommandError.strokeNotLive(missing.id)) {
            try rig.revert(AddStroke(strokes: [loaded[0], missing]))
        }
        #expect(throws: CommandError.strokeNotLive(missing.id)) {
            try rig.apply(EraseStrokes(removed: [loaded[0], missing], parts: []))
        }
        #expect(throws: CommandError.strokeAlreadyLive(loaded[0].id)) {
            try rig.apply(EraseStrokes(removed: [loaded[1]], parts: [loaded[0]]))
        }
        #expect(throws: CommandError.strokeNotLive(missing.id)) {
            try rig.revert(EraseStrokes(removed: [loaded[1]], parts: [missing]))
        }
        #expect(LiveContent(rig.content) == start)
        #expect(rig.content.erased.isEmpty)
    }

    @Test("A second erase of a stroke keeps the time of its first erase")
    func secondErase() throws {
        var rig = CommandRig()
        let stroke = try rig.load(1)[0]
        let first = rig.content.remove(stroke.id, at: rig.factory.clock.now())
        _ = try rig.content.restore(stroke, at: rig.factory.clock.now(), ignoringLimit: false)
        let second = rig.content.remove(stroke.id, at: rig.factory.clock.now())
        #expect(second.erased == first.erased)
        #expect(second.modified > first.modified)
        #expect(!second.isDeleted)
    }

    @Test("A new load takes the session records back, and an undo after it restores the stroke")
    func adoptAfterReload() throws {
        var (rig, loaded) = try Self.rig()
        let command = EraseStrokes(removed: [loaded[0]], parts: [rig.stroke(x: 70)])
        _ = try rig.apply(command)
        let session = rig.content.erased
        // The library loads the live strokes only: the parts, without the removed stroke.
        var reloaded = CanvasContent(canvasID: Fixtures.canvas)
        for stroke in rig.content.strokes.values {
            try reloaded.add(stroke)
        }
        let stale = EraseRecord(
            strokeID: loaded[1].id,
            erased: Fixtures.time,
            modified: Fixtures.time,
            isDeleted: false
        )
        #expect(
            reloaded.adoptSessionRecords(session.merging([loaded[1].id: stale]) { a, _ in a }) == 1
        )
        rig.content = reloaded
        let rows = try rig.revert(command)
        #expect(
            rows.compactMap(\.eraseRecord).allSatisfy {
                $0.strokeID == loaded[0].id ? $0.isDeleted : !$0.isDeleted
            }
        )
        #expect(rig.content.strokes[loaded[0].id] != nil)
        #expect(rows.compactMap(\.stroke).isEmpty)
    }
}
