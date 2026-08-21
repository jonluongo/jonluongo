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
    /// **It opens on the first tick and closes on the last.** A session he has
    /// opened but not logged against is not underway — he looked at it — and one
    /// where every prescribed set is ticked has nothing left to rest between.
    /// That is the bar's whole life: the first check puts it on screen, the last
    /// takes it away, and `finishedAt` is not what decides either, because he
    /// can log every set and never press Finish.
    ///
    /// The earliest is taken if somehow two qualify, so the answer is stable
    /// rather than dependent on fetch order.
    static func underway(in sessions: [Session]) -> Session? {
        sessions
            .filter { $0.startedAt != nil && $0.finishedAt == nil && !isFullyLogged($0) }
            .min { ($0.startedAt ?? .distantFuture) < ($1.startedAt ?? .distantFuture) }
    }

    /// Whether every prescribed set of this session has been ticked.
    ///
    /// **Asked of the prescription, not of a count.** Comparing how many sets
    /// were performed against how many were prescribed would call a session
    /// complete when he logged two extra sets of one movement and none of
    /// another. Every slot has to have its record.
    static func isFullyLogged(_ session: Session) -> Bool {
        let slots = SessionOrder.trainingOrder(of: session)
        return !slots.isEmpty && slots.allSatisfy { $0.record != nil }
    }
}
