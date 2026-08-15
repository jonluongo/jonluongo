import Foundation
import SwiftData
import LiftingKit

/// One set of one exercise, as the lifter logged it.
///
/// A row exists as soon as it is on screen, so `isCompleted` — not existence —
/// marks work as done, and checking it is what starts the rest timer. `load`
/// is `nil` for bodyweight movements rather than zero, so "no external weight"
/// and "an empty bar" stay distinguishable.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Mass` from Domain.
@Model
final class LoggedSet {
    var setIndex: Int = 0
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    var load: Mass?
    var reps: Int = 0
    /// Rating of perceived exertion, 1–10.
    var rpe: Double?
    var isCompleted: Bool = false
    /// Warmup sets show as "W" and are excluded from progression math.
    var isWarmup: Bool = false
    var completedAt: Date = Date()

    var exercise: PlannedExercise?

    init(
        setIndex: Int = 0, load: Mass? = nil, reps: Int = 0, rpe: Double? = nil,
        isCompleted: Bool = false, isWarmup: Bool = false, completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.load = load
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// A completed working set — the kind progression counts.
    var countsForProgression: Bool { isCompleted && !isWarmup }

    /// Estimated one-rep max via the Epley formula, in kilograms so values
    /// stay comparable across sets logged in different units.
    var estimatedOneRepMaxKilograms: Double? {
        guard let load, load.kilograms > 0, reps > 0 else { return nil }
        return load.kilograms * (1.0 + Double(reps) / 30.0)
    }
}
