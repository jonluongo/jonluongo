import Foundation
import SwiftData

/// A failure while writing to the store.
///
/// Catch this at the UI boundary and show `errorDescription` — every write in
/// this app can fail, and with CloudKit sync a conflict is an expected
/// outcome rather than an exceptional one. Depends on: Foundation and
/// SwiftData.
enum PersistenceError: Error, LocalizedError {
    case saveFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Your changes could not be saved. Check your connection and try again."
        }
    }

    /// The original error, for logging and diagnosis. Never shown to the user.
    var underlyingError: any Error {
        switch self {
        case .saveFailed(let underlying): underlying
        }
    }
}

extension ModelContext {

    /// Saves pending changes, wrapping any failure in a `PersistenceError`.
    ///
    /// Use this instead of `try? save()`. The whole point is that the failure
    /// cannot be discarded silently: a dropped save means a lifter's logged
    /// set disappears with no indication anything went wrong.
    func saveOrThrow() throws {
        do {
            try save()
        } catch {
            throw PersistenceError.saveFailed(underlying: error)
        }
    }
}
