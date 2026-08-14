import Foundation

/// One session's top-set result for an exercise, used to plot a strength
/// trend over time.
///
/// Built as part of `ExerciseTrend.build(from:)` and consumed by
/// `HistoryView`'s chart and session list. Depends on: `Mass` from Domain.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let topLoad: Mass?
    let topReps: Int
    /// Kept in kilograms (the Epley formula's stable comparison basis) rather
    /// than a display unit, so callers convert once at the point of display.
    let estimatedOneRepMaxKilograms: Double?
}

/// All logged sessions for one exercise, oldest → newest, with a best-set
/// selection per session and an improving/flat signal across the whole span.
///
/// Built by `ExerciseTrend.build(from:)` and shown by `HistoryView`'s list and
/// detail chart. Trends are keyed by `exerciseID`, never by name, so a renamed
/// or re-generated exercise doesn't fragment its own history — the same rule
/// `PerformanceHistory` enforces. `build(from:)` walks the same plan → week →
/// day → exercise hierarchy `PerformanceHistory` walks, via
/// `PerformanceHistory.allExercises(in:)`, so the two never maintain separate
/// copies of that traversal.
///
/// Every comparison here — best set, improving — is done in kilograms
/// (`Mass.kilograms`), never on `Mass` equality or raw `.value`: `Mass` never
/// canonicalizes units on storage, so two sets logged in different units must
/// be converted before they can be compared.
///
/// Depends on: `ExerciseID`, `Mass` from Domain; `TrainingPlan`,
/// `PlannedExercise`, `LoggedSet` from Store; `PerformanceHistory` from
/// Services (for the shared traversal).
struct ExerciseTrend: Identifiable {
    var id: ExerciseID { exerciseID }
    let exerciseID: ExerciseID
    /// For display only — never compared or used as a key.
    let displayName: String
    let points: [TrendPoint]

    var latestLoad: Mass? { points.last?.topLoad }

    /// True if the most recent estimated 1RM beats the first recorded one.
    var isImproving: Bool {
        guard let first = points.first?.estimatedOneRepMaxKilograms,
              let last = points.last?.estimatedOneRepMaxKilograms else { return false }
        return last > first
    }

    /// Build one trend per exercise id across all plans.
    static func build(from plans: [TrainingPlan]) -> [ExerciseTrend] {
        let loggedExercises = PerformanceHistory.allExercises(in: plans)
            .filter { !$0.completedWorkingSets.isEmpty }

        var byID: [ExerciseID: (displayName: String, points: [TrendPoint])] = [:]
        for exercise in loggedExercises {
            let logs = exercise.completedWorkingSets
            let date = logs.map(\.completedAt).max() ?? Date()
            // The "top set" is the heaviest; ties fall back to most reps.
            // Comparing `.kilograms` (not `.value` or `Mass` equality) is what
            // makes this correct when a session mixes lb- and kg-logged sets.
            let topSet = logs.max { lhs, rhs in
                (lhs.load?.kilograms ?? 0, lhs.reps) < (rhs.load?.kilograms ?? 0, rhs.reps)
            }
            let est = logs.compactMap(\.estimatedOneRepMaxKilograms).max()
            let point = TrendPoint(
                date: date,
                topLoad: topSet?.load,
                topReps: topSet?.reps ?? 0,
                estimatedOneRepMaxKilograms: est
            )
            byID[exercise.exerciseID, default: (exercise.displayName, [])].points.append(point)
        }

        return byID
            .map { id, entry in
                ExerciseTrend(
                    exerciseID: id, displayName: entry.displayName,
                    points: entry.points.sorted { $0.date < $1.date }
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}
