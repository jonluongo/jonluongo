import Foundation
import SwiftData

/// One week's worth of training, generated for a given goal.
@Model
final class WorkoutPlan {
    var createdAt: Date
    /// Snapshot of the goal text at generation time (the live prefs may change later).
    var goalSnapshot: String
    var durationMinutes: Int
    /// True when this plan was produced by the on-device model, false for the
    /// deterministic template fallback. Surfaced in the UI for transparency.
    var wasModelGenerated: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSession.plan)
    var sessions: [WorkoutSession]

    init(
        createdAt: Date = Date(),
        goalSnapshot: String,
        durationMinutes: Int,
        wasModelGenerated: Bool,
        sessions: [WorkoutSession] = []
    ) {
        self.createdAt = createdAt
        self.goalSnapshot = goalSnapshot
        self.durationMinutes = durationMinutes
        self.wasModelGenerated = wasModelGenerated
        self.sessions = sessions
    }

    /// Sessions ordered as they should appear through the week.
    var orderedSessions: [WorkoutSession] {
        sessions.sorted { $0.order < $1.order }
    }

    var isFullyCompleted: Bool {
        !sessions.isEmpty && sessions.allSatisfy { $0.completedAt != nil }
    }
}
