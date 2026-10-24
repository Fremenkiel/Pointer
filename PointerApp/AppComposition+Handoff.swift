import Foundation
import Model

extension AppComposition {
    /// What a new composition takes over from the composition that a restore replaced (D-148,
    /// D-152).
    struct Handoff {
        /// The last clock value of the old composition. The new clock continues after the
        /// larger of it and the restored `lastTimestamp`.
        let lastClock: HybridTimestamp?
        /// The message that the new composition shows, for example after a stop.
        let message: String?
        /// The pre-restore snapshot, the way back if the restored library does not open (D-20).
        let fallback: URL?
    }
}
