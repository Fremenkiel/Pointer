import Foundation
import Geometry
import Model
import Testing
import UIKit

@testable import CanvasFeature
@testable import Persistence
@testable import Pointer

/// A composition that starts as at launch on the files of a temporary folder, and the new
/// composition after each restore (tasks 2.1 to 2.4 of docs/m9-plan.md). The files of the test
/// host stay as they are.
@MainActor
final class AppHarness {
    /// The longest wait for a canvas or a new composition.
    static let timeout = Duration.seconds(10)

    let folder: URL
    let files: AppFiles
    let background = FakeBackgroundTime()
    /// The composition on the screen: the first one, or the newest after a restore.
    private(set) var composition: AppComposition
    /// The compositions that replaced the first one.
    private(set) var replacements = 0
    private var replacement: Task<Void, Never>?
    private let window: InputTrackingWindow
    /// The key window before the test, which gets the key back at the end.
    private weak var previous: UIWindow?

    /// Makes the folders, starts a composition, and waits for the canvas of its first workspace.
    static func start() async throws -> AppHarness {
        // swiftlint:disable:next arch_04_file_system
        let folder = FileManager().temporaryDirectory.appending(path: "App-\(UUID())")
        let files = AppFiles(
            library: folder.appending(path: "library.sqlite").path(percentEncoded: false),
            device: folder.appending(path: "device.sqlite").path(percentEncoded: false),
            temporary: folder.appending(path: "tmp", directoryHint: .isDirectory),
            backups: folder.appending(path: "Backups", directoryHint: .isDirectory),
            previews: folder.appending(path: "previews", directoryHint: .isDirectory)
        )
        // swiftlint:disable:next arch_04_file_system
        try FileManager().createDirectory(at: files.temporary, withIntermediateDirectories: true)
        // A window of its own, as `SceneDelegate` makes it, so that the alerts and the sheets of
        // the composition present as in the app. The window of the test host stays below.
        let host = try OnScreenCanvas.host()
        let scene = try #require(host.view.window?.windowScene)
        let window = InputTrackingWindow(windowScene: scene)
        window.frame = try #require(host.view.window?.bounds)
        let previous = scene.keyWindow
        let harness = AppHarness(folder: folder, files: files, window: window, previous: previous)
        window.makeKeyAndVisible()
        await harness.composition.start()
        try await harness.waitForCanvas()
        return harness
    }

    private init(
        folder: URL,
        files: AppFiles,
        window: InputTrackingWindow,
        previous: UIWindow?
    ) {
        self.folder = folder
        self.files = files
        self.window = window
        self.previous = previous
        composition = AppComposition(
            window: window,
            container: AppViewController(),
            defaults: .standard,
            files: files
        )
        install(composition)
    }

    /// Puts the container of `composition` on the screen and connects its replacement.
    private func install(_ composition: AppComposition) {
        window.rootViewController = composition.container
        composition.backgroundTime = background
        composition.onReplace = { [weak self] handoff in self?.replace(after: handoff) }
    }

    /// Makes the new composition after a restore, as `SceneDelegate` does.
    private func replace(after handoff: AppComposition.Handoff) {
        let next = AppComposition(
            window: window,
            container: AppViewController(),
            defaults: .standard,
            files: files
        )
        install(next)
        composition = next
        replacements += 1
        replacement = Task { await next.start(after: handoff) }
    }

    /// Waits until the newest composition started and shows a canvas.
    func waitForReplacement() async throws {
        await replacement?.value
        try await waitForCanvas()
    }

    /// Waits until the composition shows the canvas of its current workspace.
    func waitForCanvas() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while composition.container.canvas == nil || composition.container.isSwapping {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The controller at the top of the presentations of the window.
    var presented: UIViewController? {
        var top = window.rootViewController?.presentedViewController
        // A test presents at most an alert above a sheet (FLOW-03).
        for _ in 0..<4 {
            guard let next = top?.presentedViewController else { break }
            top = next
        }
        return top
    }

    /// The text of the alert on the screen, or `nil`.
    var message: String? {
        (presented as? UIAlertController)?.message
    }

    /// Closes the composition and removes the folder. SQLite must not hold the files at the
    /// delete (task 1.1).
    func remove() async {
        await replacement?.value
        do {
            try await composition.close()
        } catch {
            Issue.record("The composition did not close: \(error)")
        }
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKey()
        do {
            // swiftlint:disable:next arch_04_file_system
            try FileManager().removeItem(at: folder)
        } catch {
            Issue.record("The test folder stays behind: \(error)")
        }
    }

    /// Makes a library of another iPad in a folder of its own, with one workspace and one card
    /// at the wall time `wallMillis`, and returns a snapshot of it (D-161).
    func otherSnapshot(wallMillis: UInt64) async throws -> OtherSnapshot {
        let other = folder.appending(path: "Other-\(UUID())", directoryHint: .isDirectory)
        // swiftlint:disable:next arch_04_file_system
        try FileManager().createDirectory(at: other, withIntermediateDirectories: true)
        let wallClock = StoppedWallClock(millis: wallMillis)
        let path = other.appending(path: "library.sqlite").path(percentEncoded: false)
        let (workspace, card) = try await Self.fillLibrary(
            at: path,
            folder: other,
            wallClock: wallClock
        )
        let writer = SnapshotWriter(
            configuration: SnapshotWriter.Configuration(
                databasePath: path,
                temporaryFolder: other,
                backupsFolder: other.appending(path: "Backups", directoryHint: .isDirectory),
                wallClock: wallClock,
                timeZone: .gmt
            )
        )
        let url = try await writer.writeSnapshotNow()
        return OtherSnapshot(
            url: url,
            path: path,
            workspace: workspace,
            card: card,
            stamp: workspace.meta.created
        )
    }

    /// Makes a library of a new device at `path` with one workspace and one card at the time of
    /// `wallClock`, and closes it.
    private static func fillLibrary(
        at path: String,
        folder: URL,
        wallClock: StoppedWallClock
    ) async throws -> (Workspace, Card) {
        let device = DeviceID(rawValue: UUID())
        let repository = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: path,
                temporaryFolder: folder,
                device: device,
                wallClock: wallClock,
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
        _ = try await repository.open { _ in }
        let stamp = HybridTimestamp(wallMillis: wallClock.millis, counter: 5, device: device)
        let workspace = try Workspace(
            id: WorkspaceID(rawValue: UUID()),
            meta: RecordMeta(created: stamp),
            title: "Other",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await repository.create(workspace)
        let card = try Card(
            id: CardID(rawValue: UUID()),
            meta: RecordMeta(created: stamp),
            canvasID: workspace.canvasID,
            frame: NavigationTests.frame,
            title: "Card",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await repository.send([.card(card)])
        try await repository.saveNow()
        await repository.close()
        return (workspace, card)
    }

    /// A snapshot of another library and its rows.
    struct OtherSnapshot {
        let url: URL
        let path: String
        let workspace: Workspace
        let card: Card
        let stamp: HybridTimestamp
    }
}

/// A wall clock at a fixed time.
struct StoppedWallClock: WallClock {
    let millis: UInt64

    func nowMillis() -> UInt64 { millis }
}

/// Extra time in the background that a test controls (D-164).
@MainActor
final class FakeBackgroundTime: BackgroundTime {
    /// True if the time runs out at once, before the first step of a restore.
    var expiresAtOnce = false
    private(set) var begun = 0
    private(set) var ended = 0

    func begin(
        _ name: String,
        onExpiry: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        begun += 1
        if expiresAtOnce { onExpiry() }
        return UIBackgroundTaskIdentifier(rawValue: begun)
    }

    func end(_ task: UIBackgroundTaskIdentifier) {
        ended += 1
    }
}
