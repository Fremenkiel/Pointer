import Foundation
import Model
import Testing
import UIKit
import WorkspaceFeature

@testable import CanvasFeature
@testable import Pointer

/// Quick workspace switches load only the last canvas (F-13 of the M4 fix plan, WS-02).
@MainActor
@Suite("Canvas switches")
struct CanvasSwitchTests {
    /// The longest wait for the last canvas.
    private static let timeout = Duration.seconds(10)

    @Test("Three quick switches load one canvas and make one renderer")
    func quickSwitches() async throws {
        let host = try OnScreenCanvas.host()
        let window = try #require(host.view.window as? InputTrackingWindow)
        let library = try await D56Library.make()
        defer { await library.remove() }
        let clock = Fixtures.clock()
        let workspaces = try await Self.makeWorkspaces(in: library, clock: clock)
        let composition = AppComposition(
            window: window,
            container: AppViewController(),
            defaults: try #require(UserDefaults(suiteName: "CanvasSwitchTests"))
        )
        composition.repository = library.repository
        composition.clock = clock
        var loads: [CanvasID] = []
        composition.onLoadStarted = { loads.append($0) }
        let selector = WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: library.repository,
                makeTimestamp: { clock.now() },
                makeWorkspaceID: { clock.makeIdentifier() },
                onSwitch: { [weak composition] in composition?.open($0) }
            )
        )
        composition.selector = selector
        await selector.start(lastWorkspace: workspaces[0].id)
        try await Self.waitForCanvas(workspaces[0].canvasID, in: composition)
        loads.removeAll()
        selector.select(workspaces[1].id)
        selector.select(workspaces[2].id)
        selector.select(workspaces[0].id)
        selector.select(workspaces[2].id)
        try await Self.waitForCanvas(workspaces[2].canvasID, in: composition)
        try await Task.sleep(for: .milliseconds(500))
        #expect(loads == [workspaces[2].canvasID], "Loads: \(loads)")
    }

    @Test("A deleted workspace keeps no session, also when its canvas is on the screen (M-03)")
    func deletedWorkspace() async throws {
        let host = try OnScreenCanvas.host()
        let window = try #require(host.view.window as? InputTrackingWindow)
        let library = try await D56Library.make()
        defer { await library.remove() }
        let clock = Fixtures.clock(device: library.device)
        let workspaces = try await Self.makeWorkspaces(in: library, clock: clock)
        let composition = AppComposition(
            window: window,
            container: AppViewController(),
            defaults: try #require(UserDefaults(suiteName: "CanvasSwitchTests"))
        )
        composition.repository = library.repository
        composition.clock = clock
        let selector = WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: library.repository,
                makeTimestamp: { clock.now() },
                makeWorkspaceID: { clock.makeIdentifier() },
                onSwitch: { [weak composition] in composition?.open($0) },
                onDelete: { [weak composition] in composition?.forgetSession(of: $0) }
            )
        )
        composition.selector = selector
        await selector.start(lastWorkspace: workspaces[0].id)
        try await Self.waitForCanvas(workspaces[0].canvasID, in: composition)
        selector.select(workspaces[1].id)
        try await Self.waitForCanvas(workspaces[1].canvasID, in: composition)
        #expect(composition.sessions.hasSession(for: workspaces[0].canvasID))
        await selector.delete(workspaces[0].id)
        #expect(!composition.sessions.hasSession(for: workspaces[0].canvasID))
        // The shown workspace: the switch to the next one must not save its session again.
        await selector.delete(workspaces[1].id)
        try await Self.waitForCanvas(workspaces[2].canvasID, in: composition)
        #expect(!composition.sessions.hasSession(for: workspaces[1].canvasID))
    }

    /// Adds the workspaces A, B, and C to the library.
    private static func makeWorkspaces(
        in library: D56Library,
        clock: AppClock
    ) async throws -> [Workspace] {
        var workspaces: [Workspace] = []
        for (index, title) in ["A", "B", "C"].enumerated() {
            let workspace = try Workspace(
                id: clock.makeIdentifier(),
                meta: RecordMeta(created: clock.now(), modified: clock.now(), isDeleted: false),
                title: title,
                sortKey: FractionalIndex(rawValue: String(UnicodeScalar(UInt8(77 + index))))
            )
            try await library.repository.create(workspace)
            workspaces.append(workspace)
        }
        return workspaces
    }

    /// Waits until the container shows the canvas.
    private static func waitForCanvas(
        _ canvas: CanvasID,
        in composition: AppComposition
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while composition.container.canvas?.canvasID != canvas {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
