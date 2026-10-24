import Model
import os

/// Sends the changed rows of one canvas to the library in the order of the steps (F-11 of
/// docs/m4-fix-plan.md, storage.md section 4).
///
/// One task per step gave no order: the actor of the library runs waiting jobs by priority. Here
/// one consumer task sends each list of rows and waits for it before it takes the next.
@MainActor
final class RowChannel {
    /// One item of the channel: the rows of a step, or a flush that waits for the rows before
    /// it.
    private enum Item {
        case rows([LibraryChange])
        case flush(CheckedContinuation<Void, Never>)
    }

    private let continuation: AsyncStream<Item>.Continuation
    private let consumer: Task<Void, Never>
    private var isFinished = false

    /// Starts the consumer task for `repository`.
    init(repository: any LibraryRepository) {
        let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
        let (stream, continuation) = AsyncStream.makeStream(of: Item.self)
        self.continuation = continuation
        consumer = Task {
            do {
                for await item in stream {
                    try Task.checkCancellation()
                    guard case .rows(let rows) = item else {
                        if case .flush(let waiter) = item { waiter.resume() }
                        continue
                    }
                    do {
                        try await repository.send(rows)
                    } catch {
                        logger.error("The library did not take \(rows.count) rows: \(error)")
                    }
                }
            } catch {
                logger.error("The row channel stopped with rows left")
            }
        }
    }

    /// Queues rows behind the rows of the earlier steps.
    ///
    /// - Precondition: `rows` is not empty.
    func send(_ rows: [LibraryChange]) {
        precondition(!rows.isEmpty, "A send needs rows")
        let result = continuation.yield(.rows(rows))
        if case .terminated = result {
            assertionFailure("Rows sent after the end of the canvas")
        }
    }

    /// Returns when the library took all rows that came before the call (D-149). After
    /// `finish()`, it waits for the consumer to end.
    func flush() async {
        guard !isFinished else { return await consumer.value }
        await withCheckedContinuation { waiter in
            if case .terminated = continuation.yield(.flush(waiter)) { waiter.resume() }
        }
    }

    /// Ends the channel. The consumer sends the queued rows and then ends.
    func finish() {
        isFinished = true
        continuation.finish()
        assert(!consumer.isCancelled, "The consumer drains the queued rows")
    }
}
