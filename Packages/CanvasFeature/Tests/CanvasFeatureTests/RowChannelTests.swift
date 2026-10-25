import Foundation
import Model
import Testing

@testable import CanvasFeature

/// The end of the row channel of a canvas (review after M9, section 3.2, item 8).
@MainActor
@Suite("Row channel")
struct RowChannelTests {
    /// Makes a channel on a new library, waits for its consumer, and drops the channel without
    /// `finish()`. Returns the library weakly.
    private static func dropChannel() async -> FakeLibrary? {
        let library = FakeLibrary()
        weak let weakLibrary = library
        let channel = RowChannel(repository: library)
        await channel.flush()
        return weakLibrary
    }

    @Test("A channel that goes without finish frees its consumer and the library")
    func dropWithoutFinish() async throws {
        weak let library = await Self.dropChannel()
        for _ in 0..<2_000 where library != nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(library == nil, "The consumer task keeps the library")
    }
}
