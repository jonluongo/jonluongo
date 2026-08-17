import Foundation
import LiftingKit

/// One session's top-set result for an exercise, so a lift's sessions can be
/// laid out over time.
///
/// Built as part of `ExerciseTrend.build(from:)` and consumed by
/// `ExerciseDetailView`'s chart and session list. It carries what was lifted
/// and for how many, and nothing derived from them — no estimated one-rep max, because
/// which formula turns a set into an estimate is a training opinion and this
/// app holds none. Depends on: `Mass` from Domain.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let topLoad: Mass?
    let topReps: Int
}

/// All logged sessions for one exercise, oldest → newest, with a best-set
/// selection per session.
///
/// Built by `ExerciseTrend.build(from:)` and shown by `ExerciseDetailView`'s
/// session list and chart. Trends are keyed by `exerciseID`, never by name, so a renamed
/// or re-generated exercise doesn't fragment its own history — the same rule
/// `PerformanceHistory` enforces. `build(from:)` walks the same plan → week →
/// day → exercise hierarchy `PerformanceHistory` walks, via
/// `PerformanceHistory.allExercises(in:)`, so the two never maintain separate
/// copies of that traversal.
///
/// **It selects and orders; it does not judge.** There is no `isImproving` here
/// and no estimated one-rep max behind one. Reading whether four weeks of work
/// went anywhere means weighing load against reps against what was asked for,
/// and every formula that reduces it to one number — Epley,
/// Brzycki, Wathan — disagrees with the next. Picking one and drawing an arrow
/// from it would be this app deciding something it has no business deciding;
/// the sets are all reported in the snapshot, and the judgement is the reader's.
///
/// The best-set comparison is done in kilograms (`Mass.kilograms`), never on
/// `Mass` equality or raw `.value`: `Mass` never canonicalizes units on storage,
/// so two sets logged in different units must be converted before they can be
/// compared.
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
            let point = TrendPoint(
                date: date,
                topLoad: topSet?.load,
                topReps: topSet?.reps ?? 0
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
