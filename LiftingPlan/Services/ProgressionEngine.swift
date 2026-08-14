import Foundation

/// One logged set, reduced to a plain value for progression math (no SwiftData).
///
/// Built from a `LoggedSet` by `PerformanceHistory.history(from:)` and consumed
/// by `ProgressionEngine`. Depends on: `Mass` from Domain.
struct SetRecord: Equatable {
    /// The weight as logged, in the unit it was logged in. `nil` means bodyweight.
    var load: Mass?
    var reps: Int
    var rpe: Double?
}

/// The most recent performance on a single exercise, used to decide the next target.
///
/// Keyed by `exerciseID`, never by name — that stable identity is what lets
/// history survive an exercise catalog rename or an AI-generated plan phrasing
/// the same movement differently across regenerations. `displayName` is carried
/// only so `ProgressionEngine.performanceSummary(from:)` can name the exercise
/// in text; it must never be compared or used as a key. Produced by
/// `PerformanceHistory`, consumed by `ProgressionEngine`. Depends on:
/// `ExerciseID` from Domain.
struct ExerciseHistory: Equatable {
    var exerciseID: ExerciseID
    /// For display only — never compared or used as a key.
    var displayName: String
    /// Upper bound of the prescribed rep range (e.g. "8-12" -> 12).
    var repTargetUpper: Int
    /// Sets from the lifter's most recent session on this exercise, in order.
    var recentSets: [SetRecord]
}

/// A recommendation for how to progress an exercise next time.
///
/// Produced by `ProgressionEngine.suggestion(for:)` from an `ExerciseHistory`.
/// `suggestedLoad` carries its unit explicitly, matching the unit of the
/// heaviest recent set, so a caller never has to guess what a bare number
/// means. Depends on: `Mass` from Domain.
struct ProgressionSuggestion: Equatable {
    /// Proposed working load, or `nil` for bodyweight / "coach's call".
    var suggestedLoad: Mass?
    /// Short, motivating rationale shown to the lifter.
    var rationale: String
    /// Whether this represents an increase in demand vs. last time.
    var isPush: Bool
}

/// Pure, dependency-free progression logic. The goal is to keep nudging a casual
/// lifter toward higher intensity: add load when reps are met at a manageable
/// effort, hold when it was a grind, and stay put when reps slipped.
///
/// Consumed by the active-workout flow (via `suggestion(for:)`) to prefill the
/// next target, and by `PlanCoordinator` (via `performanceSummary(from:)`) to
/// feed recent performance back into plan generation. Depends on: `Mass` from
/// Domain, `ExerciseHistory`/`SetRecord` above.
enum ProgressionEngine {

    /// Threshold at or below which we consider a set "had more in the tank".
    static let easyRPECeiling: Double = 8.0

    /// At or above this weight, a lift is treated as heavy enough to progress
    /// in bigger jumps rather than small ones.
    static let heavyLoadThreshold: Double = 50
    /// Increment applied when a heavy lift earned a push.
    static let heavyLoadIncrement: Double = 5
    /// Increment applied when a lighter / isolation lift earned a push.
    static let lightLoadIncrement: Double = 2.5
    /// Suggested loads are snapped to this increment for plate-friendly numbers.
    static let roundingIncrement: Double = 2.5

    /// Recommend the next target for an exercise given its recent performance.
    static func suggestion(for history: ExerciseHistory) -> ProgressionSuggestion {
        let sets = history.recentSets
        let target = max(history.repTargetUpper, 1)

        guard !sets.isEmpty else {
            return ProgressionSuggestion(
                suggestedLoad: nil,
                rationale: "No history yet — pick a weight you can control for about \(target) reps.",
                isPush: false
            )
        }

        // Compare in kilograms so a history mixing kg- and lb-logged sets still
        // finds the true heaviest set, then report back in that set's own unit.
        let loggedLoads = sets.compactMap(\.load).filter { $0.kilograms > 0 }
        let minReps = sets.map(\.reps).min() ?? 0
        let rpes = sets.compactMap(\.rpe)
        let avgRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
        let hitAllReps = minReps >= target

        // Bodyweight (or unweighted) movement: progress via reps / tempo, not load.
        guard let topLoad = loggedLoads.max(by: { $0.kilograms < $1.kilograms }) else {
            if hitAllReps && (avgRPE == nil || avgRPE! <= easyRPECeiling) {
                return ProgressionSuggestion(
                    suggestedLoad: nil,
                    rationale: "You cleared \(target) reps on every set — add reps, slow the tempo, or add load next time.",
                    isPush: true
                )
            }
            return ProgressionSuggestion(
                suggestedLoad: nil,
                rationale: "Chase \(target) clean reps on all sets before making it harder.",
                isPush: false
            )
        }

        if hitAllReps && (avgRPE == nil || avgRPE! <= easyRPECeiling) {
            let increment = incrementFor(weight: topLoad.value)
            let newValue = roundToNearest(topLoad.value + increment, step: roundingIncrement)
            let newLoad = Mass(value: newValue, unit: topLoad.unit)
            let effortNote = avgRPE.map { " at RPE \(formatted($0))" } ?? ""
            return ProgressionSuggestion(
                suggestedLoad: newLoad,
                rationale: "You hit \(target)+ reps on every set\(effortNote) — step up to \(formatted(newValue)).",
                isPush: true
            )
        }

        if hitAllReps {
            return ProgressionSuggestion(
                suggestedLoad: topLoad,
                rationale: "You made the reps but it was a grind (RPE \(formatted(avgRPE ?? 9))) — own \(formatted(topLoad.value)) before adding load.",
                isPush: false
            )
        }

        return ProgressionSuggestion(
            suggestedLoad: topLoad,
            rationale: "Reps dipped to \(minReps) — stay at \(formatted(topLoad.value)) and drive for \(target) clean reps.",
            isPush: false
        )
    }

    /// A compact, prompt-friendly summary of recent performance, fed back to the
    /// model so a regenerated plan pushes intensity where it's earned.
    static func performanceSummary(from histories: [ExerciseHistory]) -> String {
        let lines = histories.compactMap { history -> String? in
            guard !history.recentSets.isEmpty else { return nil }
            let suggestion = suggestion(for: history)
            let weightText: String
            if let topLoad = history.recentSets.compactMap(\.load).max(by: { $0.kilograms < $1.kilograms }),
               topLoad.kilograms > 0 {
                weightText = "\(formatted(topLoad.value)) \(topLoad.unit.rawValue)"
            } else {
                weightText = "bodyweight"
            }
            let repsText = history.recentSets.map { String($0.reps) }.joined(separator: "/")
            let arrow = suggestion.isPush ? "↑ push" : "→ hold"
            return "- \(history.displayName): last \(weightText) for reps \(repsText) (target \(history.repTargetUpper)) [\(arrow)]"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Bigger jumps on heavier lifts, small jumps on light/isolation work.
    static func incrementFor(weight: Double) -> Double {
        weight >= heavyLoadThreshold ? heavyLoadIncrement : lightLoadIncrement
    }

    static func roundToNearest(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Format a weight without a trailing ".0" for whole numbers.
    static func formatted(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
