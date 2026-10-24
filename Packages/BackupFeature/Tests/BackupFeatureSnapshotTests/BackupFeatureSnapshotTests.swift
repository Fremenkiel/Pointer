import Testing

@testable import BackupFeature

/// The snapshot tests of the commands, the alert, and the messages of the backup (task 3.3 of
/// docs/m9-plan.md, TEST-07). They run in PointerDeviceTests on the iPad (D-77).
@Suite("Backup feature snapshots")
struct BackupFeatureSnapshotTests {
    /// A placeholder until the tasks above add the tests of this target (task 0.3).
    @Test("The test target runs on the iPad")
    func targetRuns() {
        #expect(BackupFeature.self == BackupFeature.self)
    }
}
