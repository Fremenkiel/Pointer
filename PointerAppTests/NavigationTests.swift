import Foundation
import Geometry
import Model
import Persistence
import Testing
import UIKit
import WorkspaceFeature

@testable import CanvasFeature
@testable import Pointer

/// The navigation in the card tree: the open of a card, the leave, the launch into a stored
/// path, and the history of a child (m6-plan.md task 4.4, CARD-03, CARD-04, WS-04, D-99, D-112).
@MainActor
@Suite("Card navigation")
struct NavigationTests {
    /// The longest wait for a canvas.
    private static let timeout = Duration.seconds(10)
    /// The frames of the cards of the chain, in the canvas of the card before.
    private static let frame = Rect(
        origin: Point(x: 200, y: 100),
        size: Size(width: 300, height: 210)
    )

    /// A library with one workspace and a chain of cards, each in the canvas of the card before.
    private struct Tree {
        let folder: URL
        let repository: SQLiteLibraryRepository
        let clock: AppClock
        let workspace: Workspace
        let chain: [CardID]

        func remove() {
            // swiftlint:disable:next arch_04_file_system
            try? FileManager().removeItem(at: folder)
        }
    }

    private static func makeTree(depth: Int, deleted: Int? = nil) async throws -> Tree {
        // swiftlint:disable:next arch_04_file_system
        let folder = FileManager().temporaryDirectory.appending(path: "Navigation-\(UUID())")
        // swiftlint:disable:next arch_04_file_system
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        let device = DeviceID(rawValue: UUID())
        let repository = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: folder.appending(path: "library.sqlite").path(percentEncoded: false),
                temporaryFolder: folder,
                device: device,
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
        _ = try await repository.open { _ in }
        let clock = Fixtures.clock(device: device)
        let workspace = try Workspace(
            id: clock.makeIdentifier(),
            meta: RecordMeta(created: clock.now()),
            title: "Tree",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await repository.create(workspace)
        let chain = try await addChain(
            depth,
            deleted: deleted,
            below: workspace,
            to: repository,
            clock: clock
        )
        return Tree(
            folder: folder,
            repository: repository,
            clock: clock,
            workspace: workspace,
            chain: chain
        )
    }

    /// Adds a chain of cards below the root canvas of `workspace`.
    private static func addChain(
        _ depth: Int,
        deleted: Int?,
        below workspace: Workspace,
        to repository: SQLiteLibraryRepository,
        clock: AppClock
    ) async throws -> [CardID] {
        var parent = workspace.canvasID
        var chain: [CardID] = []
        for index in 0..<depth {
            let meta = RecordMeta(created: clock.now())
            let card = try Card(
                id: clock.makeIdentifier(),
                meta: meta.changed(at: clock.now(), isDeleted: index == deleted),
                canvasID: parent,
                frame: frame,
                title: "Level \(index + 1)",
                sortKey: FractionalIndex(rawValue: "V")
            )
            try await repository.send([.card(card)])
            chain.append(card.id)
            parent = card.childCanvasID
        }
        try await repository.saveNow()
        return chain
    }

    private static func composition(for tree: Tree) throws -> AppComposition {
        let host = try OnScreenCanvas.host()
        let window = try #require(host.view.window as? InputTrackingWindow)
        let composition = AppComposition(
            window: window,
            container: AppViewController(),
            defaults: try #require(UserDefaults(suiteName: "NavigationTests"))
        )
        composition.container.view.frame = CGRect(x: 0, y: 0, width: 1_194, height: 834)
        composition.repository = tree.repository
        composition.clock = tree.clock
        // The composition shows a canvas only for the current workspace of the selector.
        let clock = tree.clock
        composition.selector = WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: tree.repository,
                makeTimestamp: { clock.now() },
                makeWorkspaceID: { clock.makeIdentifier() },
                onSwitch: { composition.open($0) }
            )
        )
        return composition
    }

    /// Waits until the container shows the canvas.
    private static func waitForCanvas(
        _ canvas: CanvasID,
        in composition: AppComposition,
        timeout: Duration = timeout
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while composition.container.canvas?.canvasID != canvas {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A double tap opens a card at the camera of CARD-03, and up leaves at CARD-04")
    func openAndLeave() async throws {
        let tree = try await Self.makeTree(depth: 1)
        defer { tree.remove() }
        let composition = try Self.composition(for: tree)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        #expect(composition.container.upButton == nil)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await Self.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        // The child is empty, so the camera of CARD-03 centers on the origin.
        #expect(composition.container.canvas?.camera == Camera(center: .zero, zoom: 1))
        #expect(composition.container.upButton != nil)
        #expect(composition.path?.level == 1)
        composition.leave()
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        #expect(composition.container.canvas?.camera == Camera(center: Self.frame.center, zoom: 1))
        #expect(composition.container.upButton == nil)
        #expect(composition.path?.level == 0)
    }

    @Test("A launch with a path of 3 cards opens level 3")
    func launchIntoPath() async throws {
        let tree = try await Self.makeTree(depth: 3)
        defer { tree.remove() }
        let composition = try Self.composition(for: tree)
        composition.launchPath = try NavigationPath(workspace: tree.workspace.id, cards: tree.chain)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(CanvasID(tree.chain[2]), in: composition)
        #expect(composition.path?.cards == tree.chain)
        #expect(composition.container.canvas?.level == 3)
        #expect(composition.container.upButton != nil)
    }

    @Test("A launch with a deleted card in the path opens the canvas above it (D-112)")
    func launchWithDeletedCard() async throws {
        let tree = try await Self.makeTree(depth: 3, deleted: 1)
        defer { tree.remove() }
        let composition = try Self.composition(for: tree)
        composition.launchPath = try NavigationPath(workspace: tree.workspace.id, cards: tree.chain)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        #expect(composition.path?.cards == [tree.chain[0]])
    }

    @Test("A child keeps its history after a leave and a new open (UNDO-02, D-12)")
    func childHistory() async throws {
        let tree = try await Self.makeTree(depth: 1)
        defer { tree.remove() }
        let composition = try Self.composition(for: tree)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await Self.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        composition.container.canvas?.addCard(at: Point(x: 10, y: 10))
        #expect(composition.container.canvas?.history.undoSteps.count == 1)
        composition.leave()
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        #expect(composition.container.canvas?.history.undoSteps.isEmpty == true)
        let again = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(again)
        try await Self.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        #expect(composition.container.canvas?.history.undoSteps.count == 1)
        #expect(composition.container.canvas?.content.cards.count == 1)
    }
}
