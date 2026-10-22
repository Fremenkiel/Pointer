import Foundation
import Geometry
import Model
import Persistence
import Rendering
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// The write of the preview of a child canvas at each leave event of D-111: the up button, the
/// pinch-out exit, the workspace switch, and the move to the background (m6-plan.md task 4.8).
@MainActor
@Suite("Preview write")
struct PreviewWriteTests {
    /// The ways to leave the child canvas.
    enum Event: CaseIterable, Sendable {
        case up, pinch, workspaceSwitch, background
    }

    /// The tree, the composition with a preview store, and the store.
    private struct Setup {
        let tree: NavigationTests.Tree
        let composition: AppComposition
        let store: PreviewStore
        let other: Workspace
    }

    /// A tree of one card with a preview store, a second workspace, and the child canvas on the
    /// screen. The preview of the empty child is in its file already.
    private static func openChild() async throws -> Setup {
        let tree = try await NavigationTests.makeTree(depth: 1)
        let other = try Workspace(
            id: tree.clock.makeIdentifier(),
            meta: RecordMeta(created: tree.clock.now()),
            title: "Other",
            sortKey: FractionalIndex(rawValue: "W")
        )
        try await tree.repository.create(other)
        let composition = try NavigationTests.composition(for: tree)
        let store = PreviewStore(folder: tree.folder.appending(path: "previews"))
        composition.previewStore = store
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        // The root canvas renders the missing preview of its card and writes it (D-107).
        _ = try await waitForPreview(of: tree, in: store) { $0 != nil }
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        return Setup(tree: tree, composition: composition, store: store, other: other)
    }

    /// Waits until the preview file of the child meets `condition`, and returns its bytes.
    private static func waitForPreview(
        of tree: NavigationTests.Tree,
        in store: PreviewStore,
        until condition: (Data?) -> Bool
    ) async throws -> Data? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        var data = await store.read(CanvasID(tree.chain[0]))
        while !condition(data) {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
            data = await store.read(CanvasID(tree.chain[0]))
        }
        return data
    }

    @Test(
        "Each leave event writes the preview of the changed child (D-111)",
        arguments: Event.allCases
    )
    func write(event: Event) async throws {
        let setup = try await Self.openChild()
        defer {
            setup.composition.container.view.removeFromSuperview()
            setup.tree.remove()
        }
        let before = try #require(await setup.store.read(CanvasID(setup.tree.chain[0])))
        let child = try #require(setup.composition.container.canvas)
        // A card in the middle of the empty child changes its preview.
        child.addCard(
            frame: Rect(origin: Point(x: -100, y: -70), size: Size(width: 200, height: 140))
        )
        switch event {
        case .up: setup.composition.leave()
        case .pinch: setup.composition.leaveByPinch()
        case .workspaceSwitch: setup.composition.selector?.select(setup.other.id)
        case .background: setup.composition.resignActive()
        }
        let after = try await Self.waitForPreview(of: setup.tree, in: setup.store) { data in
            data.map { $0 != before } ?? false
        }
        let image = try #require(after.flatMap(UIImage.init(data:)))
        // The card of the chain is 300 by 210 points, so the preview has its aspect.
        #expect(Int(image.size.width) == PreviewImage.maxSide)
        #expect(abs(image.size.width / image.size.height - 300.0 / 210.0) < 0.01)
        switch event {
        case .up, .pinch:
            try await NavigationTests.waitForCanvas(
                setup.tree.workspace.canvasID,
                in: setup.composition
            )
        case .workspaceSwitch:
            try await NavigationTests.waitForCanvas(setup.other.canvasID, in: setup.composition)
        case .background:
            #expect(setup.composition.container.canvas === child, "The child stays on the screen")
        }
    }
}
