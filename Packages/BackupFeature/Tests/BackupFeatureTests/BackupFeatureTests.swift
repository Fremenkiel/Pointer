import Testing

@testable import BackupFeature

/// The tests of the backup commands and the restore flow (tasks 2.3 and 2.4 of
/// docs/m9-plan.md). They run in PointerDeviceTests on the iPad (D-77).
@Suite("Backup feature")
struct BackupFeatureTests {
    /// A placeholder until the tasks above add the tests of this target (task 0.3).
    @Test("The test target runs on the iPad")
    func targetRuns() {
        #expect(BackupFeature.self == BackupFeature.self)
    }
}
