import Foundation

/// One logged set, reduced to a plain value for progression math (no SwiftData).
struct SetRecord: Equatable {
    var weight: Double?
    var reps: Int
    var rpe: Double?
}

/// The most recent performance on a single exercise, used to decide the next target.
struct ExerciseHistory: Equatable {
    var name: String
    /// Upper bound of the prescribed rep range (e.g. "8-12" -> 12).
    var repTargetUpper: Int
    /// Sets from the lifter's most recent session on this exercise, in order.
    var recentSets: [SetRecord]
}

/// A recommendation for how to progress an exercise next time.
struct ProgressionSuggestion: Equatable {
    /// Proposed working weight, or `nil` for bodyweight / "coach's call".
    var suggestedWeight: Double?
    /// Short, motivating rationale shown to the lifter.
    var rationale: String
    /// Whether this represents an increase in demand vs. last time.
    var isPush: Bool
}

/// Pure, dependency-free progression logic. The goal is to keep nudging a casual
/// lifter toward higher intensity: add load when reps are met at a manageable
/// effort, hold when it was a grind, and stay put when reps slipped.
enum ProgressionEngine {

    /// Threshold at or below which we consider a set "had more in the tank".
    static let easyRPECeiling: Double = 8.0

    /// Recommend the next target for an exercise given its recent performance.
    static func suggestion(for history: ExerciseHistory) -> ProgressionSuggestion {
        let sets = history.recentSets
        let target = max(history.repTargetUpper, 1)

        guard !sets.isEmpty else {
            return ProgressionSuggestion(
                suggestedWeight: nil,
                rationale: "No history yet — pick a weight you can control for about \(target) reps.",
                isPush: false
            )
        }

        let loggedWeights = sets.compactMap(\.weight).filter { $0 > 0 }
        let minReps = sets.map(\.reps).min() ?? 0
        let rpes = sets.compactMap(\.rpe)
        let avgRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
        let hitAllReps = minReps >= target

        // Bodyweight (or unweighted) movement: progress via reps / tempo, not load.
        guard let topWeight = loggedWeights.max() else {
            if hitAllReps && (avgRPE == nil || avgRPE! <= easyRPECeiling) {
                return ProgressionSuggestion(
                    suggestedWeight: nil,
                    rationale: "You cleared \(target) reps on every set — add reps, slow the tempo, or add load next time.",
                    isPush: true
                )
            }
            return ProgressionSuggestion(
                suggestedWeight: nil,
                rationale: "Chase \(target) clean reps on all sets before making it harder.",
                isPush: false
            )
        }

        if hitAllReps && (avgRPE == nil || avgRPE! <= easyRPECeiling) {
            let increment = incrementFor(weight: topWeight)
            let newWeight = roundToNearest(topWeight + increment, step: 2.5)
            let effortNote = avgRPE.map { " at RPE \(formatted($0))" } ?? ""
            return ProgressionSuggestion(
                suggestedWeight: newWeight,
                rationale: "You hit \(target)+ reps on every set\(effortNote) — step up to \(formatted(newWeight)).",
                isPush: true
            )
        }

        if hitAllReps {
            return ProgressionSuggestion(
                suggestedWeight: topWeight,
                rationale: "You made the reps but it was a grind (RPE \(formatted(avgRPE ?? 9))) — own \(formatted(topWeight)) before adding load.",
                isPush: false
            )
        }

        return ProgressionSuggestion(
            suggestedWeight: topWeight,
            rationale: "Reps dipped to \(minReps) — stay at \(formatted(topWeight)) and drive for \(target) clean reps.",
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
            if let w = history.recentSets.compactMap(\.weight).max(), w > 0 {
                weightText = "\(formatted(w)) lb"
            } else {
                weightText = "bodyweight"
            }
            let repsText = history.recentSets.map { String($0.reps) }.joined(separator: "/")
            let arrow = suggestion.isPush ? "↑ push" : "→ hold"
            return "- \(history.name): last \(weightText) for reps \(repsText) (target \(history.repTargetUpper)) [\(arrow)]"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Bigger jumps on heavier lifts, small jumps on light/isolation work.
    static func incrementFor(weight: Double) -> Double {
        weight >= 50 ? 5 : 2.5
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
