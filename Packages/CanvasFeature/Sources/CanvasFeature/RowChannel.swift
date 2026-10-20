import Model
import os

/// Sends the changed rows of one canvas to the library in the order of the steps (F-11 of
/// docs/m4-fix-plan.md, storage.md section 4).
///
/// One task per step gave no order: the actor of the library runs waiting jobs by priority. Here
/// one consumer task sends each list of rows and waits for it before it takes the next.
@MainActor
final class RowChannel {
    private let continuation: AsyncStream<[LibraryChange]>.Continuation
    private let consumer: Task<Void, Never>

    /// Starts the consumer task for `repository`.
    init(repository: any LibraryRepository) {
        let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
        let (stream, continuation) = AsyncStream.makeStream(of: [LibraryChange].self)
        self.continuation = continuation
        consumer = Task {
            do {
                for await rows in stream {
                    try Task.checkCancellation()
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
        let result = continuation.yield(rows)
        if case .terminated = result {
            assertionFailure("Rows sent after the end of the canvas")
        }
    }

    /// Ends the channel. The consumer sends the queued rows and then ends.
    func finish() {
        continuation.finish()
        assert(!consumer.isCancelled, "The consumer drains the queued rows")
    }
}
