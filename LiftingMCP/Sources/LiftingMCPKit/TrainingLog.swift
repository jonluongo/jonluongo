import Foundation
import LiftingKit

/// One logged set with everything around it: which block, which week, which
/// day, and what was prescribed at the time.
///
/// A `TrainingSnapshot` nests plans inside weeks inside days inside exercises,
/// which is the right shape to store and the wrong shape to ask questions of.
/// `TrainingLog.records(in:)` flattens it once, and `exercise_history`,
/// `recent_sessions`, `volume_by_muscle`, and the context resource all read the
/// flat form — so a set counted by one tool cannot be missed by another.
///
/// Depends on: the snapshot value types in `LiftingKit`.
struct LoggedSetRecord: Sendable {
    let planTitle: String
    let weekOrdinal: Int
    let weekLabel: String
    let isDeload: Bool
    let weekday: Weekday
    let focus: String
    let exercise: SnapshotPlannedExercise
    let loggedSet: SnapshotLoggedSet

    /// Whether this set is work rather than a warmup or a row that was put on
    /// screen and never finished. It is a statement about what the record says,
    /// not a judgement about whether the work was enough.
    var isCompletedWorkingSet: Bool { loggedSet.isCompleted && !loggedSet.isWarmup }
}

/// One training day that actually happened, with what was prescribed on it.
///
/// Produced by `TrainingLog.sessions(in:)`, newest first. A day counts as a
/// session when something was logged on it or the lifter marked it finished;
/// a day that was prescribed and never trained is not a session, because
/// reporting it as one would read as a workout of zero sets.
///
/// Depends on: the snapshot value types in `LiftingKit`.
struct SessionRecord: Sendable {
    let planTitle: String
    let weekOrdinal: Int
    let weekLabel: String
    let isDeload: Bool
    let weekday: Weekday
    let focus: String
    let durationMinutes: Int?
    let completedAt: Date?
    let lastLoggedAt: Date?
    let exercises: [SnapshotPlannedExercise]

    /// When the session happened. The last set logged is the truer answer than
    /// the day's own completion mark, which a lifter may never tap; the mark is
    /// the fallback for a day finished with nothing logged.
    var date: Date? { lastLoggedAt ?? completedAt }
}

/// Reads a `TrainingSnapshot` the way a question wants it.
///
/// Call `records(in:)` for every logged set in chronological order and
/// `sessions(in:)` for the days that happened, newest first. Everything here
/// *reports*: it re-shapes what the snapshot says and adds nothing. Nothing in
/// this file decides anything about training.
///
/// Depends on: `TrainingSnapshot` from `LiftingKit`.
enum TrainingLog {

    /// Every logged set in the snapshot, oldest first.
    ///
    /// Includes warmups and unfinished rows; each record says which it is, so a
    /// caller chooses what counts rather than being handed a filtered truth.
    static func records(in snapshot: TrainingSnapshot) -> [LoggedSetRecord] {
        var records: [LoggedSetRecord] = []
        for plan in snapshot.plans {
            for week in plan.weeks {
                for day in week.days {
                    for exercise in day.exercises {
                        for set in exercise.loggedSets {
                            records.append(
                                LoggedSetRecord(
                                    planTitle: plan.title, weekOrdinal: week.ordinal,
                                    weekLabel: week.label, isDeload: week.isDeload,
                                    weekday: day.weekday, focus: day.focus,
                                    exercise: exercise, loggedSet: set))
                        }
                    }
                }
            }
        }
        return records.sorted { $0.loggedSet.completedAt < $1.loggedSet.completedAt }
    }

    /// The days that were trained, newest first.
    static func sessions(in snapshot: TrainingSnapshot) -> [SessionRecord] {
        var sessions: [SessionRecord] = []
        for plan in snapshot.plans {
            for week in plan.weeks {
                for day in week.days {
                    let logged = day.exercises.flatMap(\.loggedSets)
                    guard !logged.isEmpty || day.completedAt != nil else { continue }
                    sessions.append(
                        SessionRecord(
                            planTitle: plan.title, weekOrdinal: week.ordinal,
                            weekLabel: week.label, isDeload: week.isDeload,
                            weekday: day.weekday, focus: day.focus,
                            durationMinutes: day.durationMinutes, completedAt: day.completedAt,
                            lastLoggedAt: logged.map(\.completedAt).max(),
                            exercises: day.exercises))
                }
            }
        }
        return sessions.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The block the lifter is on: the last one that has not been finished.
    ///
    /// `nil` when every block is finished or there are none, which is a real
    /// state — a lifter between blocks is waiting for a plan.
    static func currentBlock(in snapshot: TrainingSnapshot) -> SnapshotPlan? {
        snapshot.plans.last { $0.completedAt == nil }
    }

    /// The last completed working set on each movement the lifter has trained,
    /// newest first.
    ///
    /// This is what "current working weight" means here: the last thing he
    /// actually did, not an average, an estimate, or a projection. Warmups and
    /// unfinished rows are excluded because neither is a weight he worked with.
    static func lastWorkingSets(in snapshot: TrainingSnapshot) -> [LoggedSetRecord] {
        var latest: [ExerciseID: LoggedSetRecord] = [:]
        for record in records(in: snapshot) where record.isCompletedWorkingSet {
            // `records` is ascending, so the last one written wins.
            latest[record.exercise.exerciseID] = record
        }
        return latest.values.sorted { $0.loggedSet.completedAt > $1.loggedSet.completedAt }
    }

    /// How many whole days old the snapshot is at `now`, never negative.
    ///
    /// Reported everywhere a window is, so a reader can tell a quiet month
    /// apart from an app that has not backgrounded in a month.
    static func ageInDays(of snapshot: TrainingSnapshot, at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(snapshot.generatedAt) / (24 * 60 * 60)))
    }
}
