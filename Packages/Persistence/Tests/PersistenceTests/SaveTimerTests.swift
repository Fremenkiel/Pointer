import Testing

@testable import Persistence

@Suite("Save timer")
struct SaveTimerTests {
    @Test("The continuous timer never goes back, and a sleep to a past deadline returns at once")
    func continuous() async throws {
        let timer = ContinuousSaveTimer()
        let first = timer.now()
        try await timer.sleep(until: first)
        #expect(timer.now() >= first)
        #expect(first >= .zero)
    }

    @Test("A cancelled sleep throws")
    func cancelled() async {
        let timer = ContinuousSaveTimer()
        let task = Task { try await timer.sleep(until: timer.now() + .seconds(3600)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
