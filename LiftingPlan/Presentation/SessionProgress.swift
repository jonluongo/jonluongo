import Foundation
import SwiftData

/// Whether a session is underway, and which one.
///
/// **What it does.** Answers the one question the rest bar needs from anywhere
/// in the app: is he mid-workout, and if so which session.
///
/// **It is a fact about the record, not app state.** A session is underway
/// because something was logged against it and it has not been finished — the
/// same two fields the store already holds. Nothing has to be remembered across
/// screens, nothing can leak when a screen is dismissed, and the answer survives
/// the app being killed mid-session, which a flag on a view would not.
///
/// **What it depends on.** `Session` from Store. It holds no state and imports
/// no SwiftUI.
enum SessionProgress {

    /// The session underway, or `nil` when none is.
    ///
    /// **Started and unfinished.** A session he has opened but not logged
    /// against is not underway — he looked at it — and one he finished is over.
    /// The earliest is taken if somehow two qualify, so the answer is stable
    /// rather than dependent on fetch order.
    static func underway(in sessions: [Session]) -> Session? {
        sessions
            .filter { $0.startedAt != nil && $0.finishedAt == nil }
            .min { ($0.startedAt ?? .distantFuture) < ($1.startedAt ?? .distantFuture) }
    }
}
