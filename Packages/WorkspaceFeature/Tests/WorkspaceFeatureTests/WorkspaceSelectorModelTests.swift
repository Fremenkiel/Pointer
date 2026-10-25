import Model
import Testing

@testable import WorkspaceFeature

@MainActor
@Suite("Workspace selector model")
struct WorkspaceSelectorModelTests {
    @Test("The first launch makes a workspace named Workspace and opens it (D-52)")
    func firstLaunch() async throws {
        let fixture = SelectorFixture()
        await fixture.model.start(lastWorkspace: nil)
        #expect(fixture.model.workspaces.map(\.title) == ["Workspace"])
        #expect(fixture.model.current?.title == "Workspace")
        #expect(fixture.switches == [fixture.model.workspaces[0].id])
        #expect(try await fixture.library.workspaces().count == 1)
    }

    @Test("The launch opens the last workspace, or the first one if the last is unknown (WS-04)")
    func lastWorkspace() async throws {
        let list = try Self.three()
        let known = SelectorFixture(list)
        await known.model.start(lastWorkspace: SelectorFixture.id(2))
        #expect(known.model.current?.id == SelectorFixture.id(2))
        let unknown = SelectorFixture(list)
        await unknown.model.start(lastWorkspace: SelectorFixture.id(99))
        #expect(unknown.model.current?.id == SelectorFixture.id(1))
    }

    @Test("A switch opens the workspace and tells the app")
    func switchWorkspace() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: nil)
        fixture.model.select(SelectorFixture.id(3))
        #expect(fixture.model.current?.id == SelectorFixture.id(3))
        #expect(fixture.switches == [SelectorFixture.id(1), SelectorFixture.id(3)])
    }

    @Test("A new workspace goes to the end of the list with a trimmed title and opens")
    func create() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: nil)
        await fixture.model.create(title: "  Graphs \n")
        let created = try #require(fixture.model.workspaces.last)
        #expect(created.title == "Graphs")
        #expect(created.sortKey > fixture.model.workspaces[2].sortKey)
        #expect(fixture.model.current == created)
        #expect(try await fixture.library.workspaces().last == created)
    }

    @Test(
        "A title that is empty after the trim or too long shows a message",
        arguments: ["  ", String(repeating: "x", count: 121)]
    )
    func invalidTitle(title: String) async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: nil)
        await fixture.model.create(title: title)
        #expect(fixture.model.message == .invalidTitle)
        #expect(fixture.model.workspaces.count == 3)
        await fixture.model.rename(SelectorFixture.id(1), to: title)
        #expect(fixture.model.workspaces[0].title == "Alpha")
        fixture.model.dismissMessage()
        #expect(fixture.model.message == nil)
    }

    @Test("A rename trims the title and changes the current workspace too")
    func rename() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: SelectorFixture.id(2))
        await fixture.model.rename(SelectorFixture.id(2), to: " Lists ")
        #expect(fixture.model.current?.title == "Lists")
        #expect(fixture.model.workspaces.map(\.title) == ["Alpha", "Lists", "Gamma"])
        #expect(try await fixture.library.workspaces()[1].title == "Lists")
    }

    @Test("A delete of another workspace keeps the current one")
    func deleteOther() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: SelectorFixture.id(2))
        await fixture.model.delete(SelectorFixture.id(3))
        #expect(fixture.model.current?.id == SelectorFixture.id(2))
        #expect(await fixture.library.deleted == [SelectorFixture.id(3)])
    }

    @Test("A delete of the current workspace opens the first one of the list (D-52)")
    func deleteCurrent() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: SelectorFixture.id(2))
        await fixture.model.delete(SelectorFixture.id(2))
        #expect(fixture.model.current?.id == SelectorFixture.id(1))
        #expect(fixture.model.workspaces.map(\.title) == ["Alpha", "Gamma"])
    }

    @Test("A delete of the last workspace makes a new one named Workspace (D-52)")
    func deleteLast() async throws {
        let fixture = SelectorFixture([try SelectorFixture.workspace(1, "Alpha", key: "V")])
        await fixture.model.start(lastWorkspace: nil)
        await fixture.model.delete(SelectorFixture.id(1))
        #expect(fixture.model.workspaces.map(\.title) == ["Workspace"])
        #expect(fixture.model.current?.title == "Workspace")
    }

    @Test("At 1,000 workspaces, a new one is refused with a message and no write")
    func limit() async throws {
        var list: [Workspace] = []
        var key: FractionalIndex?
        for index in 0..<Limits.maxWorkspaces {
            key = try FractionalIndex.between(key, nil)
            list.append(
                try Workspace(
                    id: WorkspaceID(
                        rawValue: .init(
                            uuid: (
                                6, UInt8(index >> 8), UInt8(index & 0xFF), 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0
                            )
                        )
                    ),
                    meta: RecordMeta(
                        created: HybridTimestamp(
                            wallMillis: 1,
                            counter: 0,
                            device: SelectorFixture.device
                        )
                    ),
                    title: "W",
                    sortKey: try #require(key)
                )
            )
        }
        let fixture = SelectorFixture(list)
        await fixture.model.start(lastWorkspace: nil)
        #expect(!fixture.model.canCreate)
        await fixture.model.create(title: "One more")
        #expect(fixture.model.message == .limitReached)
        #expect(await fixture.library.createCalls == 0)
    }

    @Test("A storage error shows a message and leaves the list as it was")
    func storageError() async throws {
        let fixture = SelectorFixture(try Self.three())
        await fixture.model.start(lastWorkspace: nil)
        await fixture.library.fail(with: .storageFailed(reason: "disk full"))
        await fixture.model.delete(SelectorFixture.id(2))
        #expect(fixture.model.message == .storageFailed)
        #expect(fixture.model.workspaces.count == 3)
        await fixture.library.fail(with: .libraryIsReadOnly)
        await fixture.model.create(title: "New")
        #expect(fixture.model.message == .readOnly)
        await fixture.library.fail(with: .workspaceLimitReached)
        await fixture.model.create(title: "New")
        #expect(fixture.model.message == .limitReached)
    }

    @Test("A failed load shows a message and lists nothing")
    func failedLoad() async {
        let fixture = SelectorFixture()
        await fixture.library.fail(with: .storageFailed(reason: "damaged"))
        await fixture.model.start(lastWorkspace: nil)
        #expect(fixture.model.message == .storageFailed)
        #expect(fixture.model.current == nil)
    }

    @Test("The limit messages show the limits of Limits (STYLE-03)")
    func limitMessages() {
        #expect(WorkspaceStrings.limitReached.contains(Limits.maxWorkspaces.formatted()))
        #expect(WorkspaceStrings.invalidTitle.contains(Limits.maxTitleLength.formatted()))
        #expect(!WorkspaceStrings.limitReached.contains("%"))
    }

    static func three() throws -> [Workspace] {
        [
            try SelectorFixture.workspace(1, "Alpha", key: "V"),
            try SelectorFixture.workspace(2, "Beta", key: "W"),
            try SelectorFixture.workspace(3, "Gamma", key: "X"),
        ]
    }
}
