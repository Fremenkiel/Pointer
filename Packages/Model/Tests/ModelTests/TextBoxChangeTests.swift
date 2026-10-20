import Geometry
import Testing

@testable import Model

@Suite("Text box changes")
struct TextBoxChangeTests {
    private static let later = HybridTimestamp(
        wallMillis: Fixtures.time.wallMillis + 1,
        counter: 0,
        device: Fixtures.device
    )

    @Test("An edit keeps the ID, the creation, and the origin, and sets the change time")
    func edit() throws {
        let box = try RecordTests.textBox(text: "old")
        let edited = try box.editing(text: "new", at: Self.later)
        #expect(edited.id == box.id)
        #expect(edited.text == "new")
        #expect(edited.origin == box.origin)
        #expect(edited.meta.created == box.meta.created)
        #expect(edited.meta.modified == Self.later)
        #expect(!edited.meta.isDeleted)
    }

    @Test(
        "An edit takes 1 and the limit of code points and refuses 0 and the limit plus one",
        arguments: [0, 1, Limits.maxTextLength, Limits.maxTextLength + 1]
    )
    func editLength(length: Int) throws {
        let box = try RecordTests.textBox(text: "old")
        let text = String(repeating: "a", count: length)
        if (1...Limits.maxTextLength).contains(length) {
            #expect(try box.editing(text: text, at: Self.later).text == text)
        } else {
            #expect(throws: ModelError.invalidText(length: length)) {
                try box.editing(text: text, at: Self.later)
            }
        }
    }

    @Test("An edit refuses U+0000 (D-57)")
    func editNull() throws {
        let box = try RecordTests.textBox(text: "old")
        #expect(throws: ModelError.nullCharacter) {
            try box.editing(text: "a\u{0}b", at: Self.later)
        }
    }

    @Test("A move sets the origin and refuses an origin that is not finite")
    func move() throws {
        let box = try RecordTests.textBox(text: "box")
        let moved = try box.moving(to: Point(x: -5, y: 9), at: Self.later)
        #expect(moved.origin == Point(x: -5, y: 9))
        #expect(moved.text == box.text)
        #expect(moved.meta.modified == Self.later)
        #expect(throws: ModelError.invalidGeometry(reason: "text box origin")) {
            try box.moving(to: Point(x: .infinity, y: 0), at: Self.later)
        }
    }

    @Test("A mark sets and clears the tombstone flag", arguments: [true, false])
    func mark(isDeleted: Bool) throws {
        let box = try RecordTests.textBox(text: "box")
        let marked = box.marking(deleted: isDeleted, at: Self.later)
        #expect(marked.meta.isDeleted == isDeleted)
        #expect(marked.meta.modified == Self.later)
        #expect(marked.meta.created == box.meta.created)
    }

    @Test("A replace changes the live box and returns the box before it")
    func replace() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let box = try RecordTests.textBox(text: "old")
        try content.add(box)
        let earlier = content.replace(try box.editing(text: "new", at: Self.later))
        #expect(earlier == box)
        #expect(content.textBoxes[box.id]?.text == "new")
        #expect(content.textBoxes.count == 1)
    }

    @Test("A removed box leaves the content, and an add puts it back")
    func removeAndAdd() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let box = try RecordTests.textBox(text: "box")
        try content.add(box)
        #expect(content.removeTextBox(box.id) == box)
        #expect(content.textBoxes.isEmpty)
        #expect(content.nodeCount == 0)
        try content.add(box)
        #expect(content.textBoxes[box.id] == box)
    }

    @Test("The text style has the values of D-15 and D-83")
    func style() {
        #expect(TextStyle.fontSize == 17)
        #expect(TextStyle.maxWidth == 640)
    }
}
