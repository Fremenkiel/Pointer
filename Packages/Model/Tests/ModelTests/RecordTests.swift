import Foundation
import Geometry
import Testing

@testable import Model

@Suite("Records and their limits")
struct RecordTests {
    @Test(
        "A workspace title has 1 to 120 code points after the trim",
        arguments: [(0, false), (1, true), (Limits.maxTitleLength, true), (121, false)]
    )
    func workspaceTitle(length: Int, isValid: Bool) throws {
        let title = "  " + String(repeating: "a", count: length) + "\n"
        let make = { () throws(ModelError) -> Workspace in
            try Workspace(
                id: Fixtures.id(1),
                meta: Fixtures.meta,
                title: title,
                sortKey: .init(rawValue: "V")
            )
        }
        if isValid {
            #expect(try make().title == String(repeating: "a", count: length))
        } else {
            #expect(throws: ModelError.invalidTitle(length: length)) { try make() }
        }
    }

    @Test("A title counts Unicode code points, so 61 flags are too long (D-57)")
    func titleCountsCodePoints() throws {
        let flags60 = String(repeating: "\u{1F1E9}\u{1F1F0}", count: 60)
        let workspace = try Workspace(
            id: Fixtures.id(1),
            meta: Fixtures.meta,
            title: flags60,
            sortKey: Fixtures.key()
        )
        #expect(workspace.title.count == 60)
        #expect(throws: ModelError.invalidTitle(length: 122)) {
            try Workspace.validatedTitle(flags60 + "\u{1F1E9}\u{1F1F0}")
        }
    }

    @Test("A workspace and its root canvas have the same ID")
    func workspaceCanvas() throws {
        let workspace = try Workspace(
            id: Fixtures.id(4),
            meta: Fixtures.meta,
            title: "Notes",
            sortKey: Fixtures.key()
        )
        #expect(workspace.canvasID.rawValue == workspace.id.rawValue)
    }

    @Test(
        "A card title has 0 to 120 code points or none",
        arguments: [(nil, true), (0, true), (1, true), (Limits.maxTitleLength, true), (121, false)]
    )
    func cardTitle(length: Int?, isValid: Bool) throws {
        let title = length.map { String(repeating: "b", count: $0) }
        let make = { () throws(ModelError) -> Card in
            try Self.card(title: title)
        }
        if isValid {
            #expect(try make().title == title)
        } else {
            #expect(throws: ModelError.invalidTitle(length: 121)) { try make() }
        }
    }

    @Test(
        "A card is at least 64 by 48 canvas points with a finite frame",
        arguments: [
            (64.0, 48.0, true), (63.9, 48.0, false), (64.0, 47.9, false), (0.0, 0.0, false),
            (Double.infinity, 48.0, false), (64.0, Double.infinity, false),
        ]
    )
    func cardSize(width: Double, height: Double, isValid: Bool) throws {
        let frame = Rect(origin: Point(x: -5, y: 7), size: Size(width: width, height: height))
        if isValid {
            #expect(try Self.card(frame: frame).frame == frame)
        } else {
            #expect(throws: ModelError.self) { try Self.card(frame: frame) }
        }
    }

    @Test("A card with an origin that is not finite is refused")
    func cardOrigin() {
        let frame = Rect(origin: Point(x: .nan, y: 0), size: Size(width: 64, height: 48))
        #expect(throws: ModelError.invalidGeometry(reason: "card frame is not finite")) {
            try Self.card(frame: frame)
        }
    }

    @Test("A card cannot lie on its own child canvas")
    func cardOwnCanvas() throws {
        let id: CardID = Fixtures.id(9)
        #expect(throws: ModelError.cardIsOwnCanvas) {
            try Self.card(id: id, canvasID: CanvasID(id))
        }
        #expect(try Self.card(id: id).childCanvasID == CanvasID(id))
    }

    @Test(
        "A text box text has 1 to 10,000 code points",
        arguments: [(0, false), (1, true), (Limits.maxTextLength, true), (10_001, false)]
    )
    func textLength(length: Int, isValid: Bool) throws {
        let text = String(repeating: "c", count: length)
        if isValid {
            #expect(try Self.textBox(text: text).text == text)
        } else {
            #expect(throws: ModelError.invalidText(length: length)) {
                try Self.textBox(text: text)
            }
        }
    }

    @Test("A text box with an origin that is not finite is refused")
    func textBoxOrigin() {
        #expect(throws: ModelError.invalidGeometry(reason: "text box origin")) {
            try Self.textBox(text: "x", origin: Point(x: 0, y: .infinity))
        }
    }

    @Test(
        "A navigation path has at most 32 cards",
        arguments: [0, 1, Limits.maxDepth, 33]
    )
    func navigationPath(count: Int) throws {
        let path: [CardID] = (0..<count).map { Fixtures.id(UInt8($0)) }
        let make = { () throws(ModelError) -> DeviceState in
            try DeviceState(deviceID: Fixtures.device, lastWorkspace: nil, navigationPath: path)
        }
        if count <= Limits.maxDepth {
            #expect(try make().navigationPath == path)
        } else {
            #expect(throws: ModelError.navigationPathTooLong(count: count)) { try make() }
        }
    }

    @Test("A new record was created and last changed at the same time and is live")
    func newMeta() {
        let meta = RecordMeta(created: Fixtures.time)
        #expect(meta.modified == meta.created)
        #expect(!meta.isDeleted)
    }

    @Test("An erase record keeps its stroke and its clock values")
    func eraseRecord() {
        let later = HybridTimestamp(
            wallMillis: 1_700_000_000_001,
            counter: 0,
            device: Fixtures.device
        )
        let record = EraseRecord(
            strokeID: Fixtures.id(5),
            erased: Fixtures.time,
            modified: later,
            isDeleted: true
        )
        #expect(record.strokeID == Fixtures.id(5))
        #expect(record.erased < record.modified)
        #expect(record.isDeleted)
    }

    static func card(
        id: CardID = Fixtures.id(2),
        canvasID: CanvasID = Fixtures.canvas,
        frame: Rect = Rect(origin: .zero, size: Size(width: 64, height: 48)),
        title: String? = nil
    ) throws(ModelError) -> Card {
        try Card(
            id: id,
            meta: Fixtures.meta,
            canvasID: canvasID,
            frame: frame,
            title: title,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    static func textBox(
        id: TextBoxID = Fixtures.id(3),
        text: String,
        origin: Point = Point(x: 1, y: 2)
    ) throws(ModelError) -> TextBox {
        try TextBox(
            id: id,
            meta: Fixtures.meta,
            canvasID: Fixtures.canvas,
            origin: origin,
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }
}
