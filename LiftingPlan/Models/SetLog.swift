import Foundation
import SwiftData

/// A single set row. Unlike a write-once log, a row exists as soon as it's on
/// screen (editable weight/reps) and is marked `isCompleted` when the lifter
/// checks it off — which is also what starts the rest timer.
@Model
final class SetLog {
    /// Row order within the exercise (0-based), including warmups.
    var setIndex: Int
    /// Weight used. `nil` for bodyweight movements.
    var weight: Double?
    var reps: Int
    /// Rating of Perceived Exertion (1–10), optional.
    var rpe: Double?
    /// Whether the lifter has checked this set off as done.
    var isCompleted: Bool
    /// Warmup sets are shown as "W" and excluded from progression math.
    var isWarmup: Bool
    /// When the set was completed (updated on check-off).
    var completedAt: Date

    var exercise: PlannedExercise?

    init(
        setIndex: Int,
        weight: Double?,
        reps: Int,
        rpe: Double? = nil,
        isCompleted: Bool = false,
        isWarmup: Bool = false,
        completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// A completed working set — the kind that counts toward progression.
    var countsForProgression: Bool { isCompleted && !isWarmup }

    /// Estimated one-rep max via the Epley formula. Useful for tracking trend
    /// even when rep counts vary session to session.
    var estimatedOneRepMax: Double? {
        guard let weight, weight > 0, reps > 0 else { return nil }
        return weight * (1.0 + Double(reps) / 30.0)
    }
}
