import Foundation
import SwiftData

/// A single logged set: what the lifter actually did.
@Model
final class SetLog {
    /// 0-based position of this set within its exercise.
    var setIndex: Int
    /// Weight used. `nil` for bodyweight movements.
    var weight: Double?
    var reps: Int
    /// Rating of Perceived Exertion (1–10), optional. Drives progression decisions.
    var rpe: Double?
    var completedAt: Date

    var exercise: PlannedExercise?

    init(
        setIndex: Int,
        weight: Double?,
        reps: Int,
        rpe: Double? = nil,
        completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completedAt = completedAt
    }

    /// Estimated one-rep max via the Epley formula. Useful for tracking trend
    /// even when rep counts vary session to session.
    var estimatedOneRepMax: Double? {
        guard let weight, weight > 0, reps > 0 else { return nil }
        return weight * (1.0 + Double(reps) / 30.0)
    }
}
