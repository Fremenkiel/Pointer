import Foundation
import Model
import Testing

@testable import Persistence

/// M3 acceptance 1: a force quit loses at most 2 seconds of ink (STO-06, D-54).
///
/// This acceptance test needs the real clock and a real process, because it stops a process
/// that saves through the repository. It takes about 10 seconds.
@Suite("Crash test")
struct CrashTests {
    /// The time of strokes without a pause before the stop (M3 acceptance 1).
    static let drawingTime = Duration.seconds(10)
    /// The most work that a crash can lose (STO-06).
    static let maxLossMillis: UInt64 = 2_000
    /// The most lines of output before the ready line (FLOW-03).
    static let maxLines = 10

    @Test("A stop with SIGKILL after 10 seconds of strokes loses at most 2 seconds")
    func killDuringStrokes() async throws {
        let folder = try TemporaryFolder()
        let path = folder.path("library.sqlite")
        let helper = try Self.productsFolder().appending(path: "PersistenceCrashHelper")
        let process = Process()
        process.executableURL = helper
        process.arguments = [path, folder.url.path(percentEncoded: false)]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        try await Self.waitForReady(output)

        try await Task.sleep(for: Self.drawingTime)
        let killMillis = SystemWallClock().nowMillis()
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)

        let library = try SQLiteConnection(path: path, mode: .readWrite)
        let saved = try library.integer("SELECT count(*) FROM stroke")
        let newest = try ValueCodec.timestamp(
            try #require(try Self.newestCreated(library))
        ).wallMillis
        let lost = killMillis - newest
        let line = "crash test: \(saved) strokes saved, the newest \(lost) ms before the kill\n"
        FileHandle.standardError.write(Data(line.utf8))
        #expect(lost <= Self.maxLossMillis, "\(line)")
        #expect(saved > 500, "\(line)")
    }

    /// Returns the folder of the build products: the parent of the test bundle, where the
    /// helper binary lies.
    static func productsFolder() throws -> URL {
        var url = Bundle.module.bundleURL
        for _ in 0..<maxLines where url.pathExtension != "xctest" {
            url = url.deletingLastPathComponent()
        }
        #expect(url.pathExtension == "xctest", "No test bundle above \(Bundle.module.bundleURL)")
        return url.deletingLastPathComponent()
    }

    private static func waitForReady(_ output: Pipe) async throws {
        var lines = 0
        for try await line in output.fileHandleForReading.bytes.lines {
            try Task.checkCancellation()
            lines += 1
            if line == "ready" || lines >= maxLines { break }
        }
        #expect(lines < maxLines, "The helper did not get ready")
    }

    private static func newestCreated(_ library: SQLiteConnection) throws -> Data? {
        let statement = try library.prepare("SELECT max(created) FROM stroke")
        guard try statement.step() else { return nil }
        return statement.data(at: 0)
    }
}
