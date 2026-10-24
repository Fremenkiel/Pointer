import Foundation
import Testing
import UIKit

@testable import Persistence
@testable import Pointer

/// "Back up now" (task 2.4 of docs/m9-plan.md, STO-04, D-155, D-160).
@MainActor
@Suite("Back up now", .serialized)
struct BackUpNowTests {
    @Test("The flow writes a daily snapshot and shows it in the share sheet")
    func backUpAndShare() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let url = try #require(await harness.composition.backUpNow()).get()
        #expect(url.deletingLastPathComponent().path == harness.files.backups.path)
        #expect(SnapshotFiles.isDaily(url.lastPathComponent))
        let reader = try SQLiteConnection(path: url.path(percentEncoded: false), mode: .readOnly)
        #expect(try reader.text("PRAGMA integrity_check") == "ok")
        #expect(try reader.integer("SELECT count(*) FROM workspace") == 1)
        harness.composition.share(url, at: CGRect(x: 20, y: 20, width: 44, height: 44))
        // The sheet loads its activities before it shows.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: AppHarness.timeout)
        // The flag follows when the presentation ends.
        let isShown = {
            harness.presented is UIActivityViewController && harness.composition.isSharing
        }
        while !isShown(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.presented is UIActivityViewController)
        #expect(harness.composition.sharedSnapshot == url)
        #expect(harness.composition.isSharing)
    }
}
