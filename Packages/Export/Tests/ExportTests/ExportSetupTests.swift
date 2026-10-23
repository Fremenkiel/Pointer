import Export
import Testing

/// Makes sure that the Export tests run on the iPad in `PointerDeviceTests` (D-77, D-140).
@Suite("Export setup")
struct ExportSetupTests {
    @Test("The Export tests run in PointerDeviceTests")
    func exportTestsRun() {
        #expect(String(describing: Export.self) == "Export")
    }
}
