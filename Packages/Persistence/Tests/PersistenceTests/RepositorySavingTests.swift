import Foundation
import Model
import Testing

@testable import Persistence

@Suite("Repository saves")
struct RepositorySavingTests {
    @Test("Sent rows are saved in one transaction and load again after a new open")
    func roundTrip() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let card = try Values.card(3)
        let textBox = try Values.textBox(5)
        try await repository.send([.stroke(Values.stroke(6)), .card(card), .textBox(textBox)])
        try await repository.saveNow()
        #expect(await repository.pendingCount == 0)

        let again = harness.make()
        let launch = try await again.open { _ in }
        #expect(launch == LibraryLaunch(isReadOnly: false, lastTimestamp: Values.late))
        let content = try await again.content(of: Values.canvas)
        #expect(Array(content.strokes.keys) == [Values.id(6)])
        #expect(content.cards[card.id] == card)
        #expect(content.textBoxes[textBox.id] == textBox)
    }

    @Test("A failure between the last row and COMMIT leaves the state before the transaction")
    func crashBeforeCommit() async throws {
        let harness = try RepositoryHarness()
        let failSwitch = FailSwitch()
        let repository = try await harness.open(failSwitch: failSwitch)
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        try await repository.saveNow()

        failSwitch.set(true)
        try await repository.send([.stroke(Values.stroke(2, millis: 20))])
        await #expect(throws: ModelError.self) { try await repository.saveNow() }
        let reader = try harness.reader()
        #expect(try reader.integer("SELECT count(*) FROM stroke") == 1)
        let stored = try reader.text("SELECT value FROM library WHERE key = 'lastTimestamp'")
        #expect(try ValueCodec.timestamp(hex: stored).wallMillis == RepositoryHarness.now)
        #expect(await repository.pendingCount == 1)

        failSwitch.set(false)
        try await repository.saveNow()
        #expect(try reader.integer("SELECT count(*) FROM stroke") == 2)
        #expect(await repository.pendingCount == 0)
    }

    @Test("A row that fails in the middle of the write rolls back, and the rows stay pending")
    func failureInsideWrite() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        try await repository.saveNow()

        // The erase record names a stroke that is not in the file, so its foreign key fails
        // after the stroke row is written.
        let orphan = EraseRecord(
            strokeID: Values.id(9),
            erased: Values.late,
            modified: Values.late,
            isDeleted: false
        )
        try await repository.send([.stroke(Values.stroke(2, millis: 20)), .erase(orphan)])
        await #expect(throws: ModelError.self) { try await repository.saveNow() }
        #expect(try harness.reader().integer("SELECT count(*) FROM stroke") == 1)
        #expect(await repository.pendingCount == 2)
    }

    @Test("A failed saveNow schedules a new try, and the row is saved after the interval (F-09)")
    func failedSaveNowRetries() async throws {
        let harness = try RepositoryHarness()
        let failSwitch = FailSwitch()
        let repository = try await harness.open(failSwitch: failSwitch)
        // The first send saves at once, so the second one waits for the throttle.
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        failSwitch.set(true)
        try await repository.send([.stroke(Values.stroke(2, millis: 20))])
        await #expect(throws: ModelError.self) { try await repository.saveNow() }
        failSwitch.set(false)
        for _ in 0..<5 {
            harness.timer.advance(by: .seconds(1))
            await repository.settle()
        }
        #expect(await repository.pendingCount == 0)
        #expect(try harness.reader().integer("SELECT count(*) FROM stroke") == 2)
    }

    @Test("Three failed saves in a row report a fault, and the next good save reports recovery")
    func failureFault() async throws {
        let harness = try RepositoryHarness()
        let failSwitch = FailSwitch()
        let repository = try await harness.open(failSwitch: failSwitch)
        failSwitch.set(true)
        // The send saves at once, because no save ran before. That is the first failure.
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        for _ in 1..<SQLiteLibraryRepository.failuresBeforeFault {
            await #expect(throws: ModelError.self) { try await repository.saveNow() }
        }
        failSwitch.set(false)
        try await repository.saveNow()
        var faults = harness.faults.makeAsyncIterator()
        let first = await faults.next()
        guard case .savesFailing(let count, let reason) = first else {
            Issue.record("Expected savesFailing, got \(String(describing: first))")
            return
        }
        #expect(count == 3)
        #expect(reason.contains("injected failure"))
        #expect(await faults.next() == .savesRecovered)
    }

    @Test("A failed save tries again at the end of the interval without a new row")
    func retry() async throws {
        let harness = try RepositoryHarness()
        let failSwitch = FailSwitch()
        let repository = try await harness.open(failSwitch: failSwitch)
        failSwitch.set(true)
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        #expect(await repository.pendingCount == 1)
        failSwitch.set(false)
        harness.timer.advance(by: .seconds(1))
        await repository.settle()
        #expect(await repository.pendingCount == 0)
    }

    @Test("A pencil lift saves at once after a quiet second, else at the end of the second")
    func pencilLift() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        #expect(await repository.pendingCount == 0)
        harness.timer.advance(by: .milliseconds(300))
        try await repository.send([.stroke(Values.stroke(2, millis: 20))])
        await repository.requestSave()
        #expect(await repository.pendingCount == 1)
        harness.timer.advance(by: .milliseconds(700))
        await repository.settle()
        #expect(await repository.pendingCount == 0)
    }

    @Test("Ten seconds of strokes without a pause lose at most one second at any moment (STO-06)")
    func throttle() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let reader = try harness.reader()
        let step = Duration.milliseconds(100)
        var sentMillis: [Int64] = []
        var sawThrottle = false
        for index in 1...100 {
            harness.timer.advance(by: step)
            await repository.settle()
            let millis = Int64(index * 100)
            try await repository.send([.stroke(Values.stroke(UInt8(index), millis: UInt64(millis)))]
            )
            sentMillis.append(millis)
            let saved = try reader.integer("SELECT count(*) FROM stroke")
            let olderThanOneSecond = sentMillis.filter { $0 <= millis - 1000 }.count
            #expect(saved >= olderThanOneSecond, "At \(millis) ms, \(saved) saved")
            sawThrottle = sawThrottle || saved < sentMillis.count
        }
        #expect(sawThrottle, "The throttle never held a row back")
        let saved = try reader.integer("SELECT count(*) FROM stroke")
        #expect(sentMillis.count - Int(saved) <= 10)
    }
}
