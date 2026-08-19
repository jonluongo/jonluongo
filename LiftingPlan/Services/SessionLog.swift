import Foundation
import SwiftData
import LiftingKit

/// Everything logging a session *does*, as opposed to how it looks.
///
/// **What it does.** Owns the two jobs the logging screen was carrying besides
/// layout: writing to the record — seeding rows, adding a set or a round,
/// deleting one, finishing and un-finishing — and running the clock the
/// prescription asks for when a set is ticked. Nothing here draws.
///
/// **How it is used.** `ActiveWorkoutView` builds one per redraw from the
/// context and the two environment objects it already holds, then calls it.
/// Every write is `throws`: a failed save is shown to the lifter by the view
/// that can show it, rather than being handled by a type with no way to say so.
/// The view was 316 lines doing five jobs, and every screen-level defect in this
/// app has been in it or its neighbours — which is what one file with five
/// responsibilities produces.
///
/// **It decides nothing about training.** How long to rest is Claude's to
/// prescribe and the lifter's to override, in that order, and this only asks
/// `RestPreferences` which of the two answers applies. Where neither has said
/// anything, no clock starts: the app does not invent one.
///
/// **What it depends on.** `WorkoutDay`, `PlannedExercise` and `LoggedSet` from
/// Store, `ExerciseGroup` for a group's rounds,
/// `SetSeeding` for what a new row starts as, and the rest timer and
/// preferences it is handed.
@MainActor
struct SessionLog {

    let day: WorkoutDay
    let context: ModelContext
    let restTimer: RestTimerModel
    let restPreferences: RestPreferences
    /// Every block, for the one question a group's rest asks that reaches
    /// outside this session.

    // MARK: - Writing to the record

    /// Fills the table in from the prescription the first time this session is
    /// opened. What each row starts as is `SetSeeding`'s rule, not this one's.
    func seedIfNeeded() throws {
        SetSeeding.seedMissingSets(for: day.orderedExercises, in: context)
        try context.saveOrThrow()
    }

    func addSet(to exercise: PlannedExercise, warmup: Bool) throws {
        SetSeeding.addSet(to: exercise, warmup: warmup, in: context)
        try context.saveOrThrow()
    }


    /// Marks the session trained. The first finish stamps the time and a later
    /// one leaves it: when he trained is a fact, and re-finishing a corrected
    /// session does not move it.
    func finish() throws {
        restTimer.stop()
        if day.completedAt == nil {
            day.completedAt = Date()
        }
        try context.saveOrThrow()
    }

    /// Takes a finished session back to unfinished, which is what makes
    /// reopening one mean anything.
    func unfinish() throws {
        day.completedAt = nil
        try context.saveOrThrow()
    }

    // MARK: - Ticking a set

    /// Writes the tick, then runs the rest it asks for.
    ///
    /// **The write is the point.** A ticked set is the one irreversible thing a
    /// lifter does in this app — it is the claim that the work happened — and
    /// until now nothing saved it. `SetRowView` flipped the flag and the
    /// callback only started a countdown, leaving the record to SwiftData's
    /// autosave, which does run but on no schedule anyone can promise. A set
    /// performed and then lost is the one failure a datastore may not have, and
    /// "probably, eventually" is not the standard.
    ///
    /// It throws so the view shows a failed save rather than swallowing it,
    /// which matters more here than anywhere else in the app.
    func completionChanged(for exercise: PlannedExercise, isCompleted: Bool) throws {
        restChanged(for: exercise, isCompleted: isCompleted)
        try context.saveOrThrow()
    }

    /// The same for a movement inside a group, where the rest waits for the
    /// round rather than the set.
    func roundCompletionChanged(_ group: ExerciseGroup, completed: Bool) throws {
        roundChanged(group, completed: completed)
        try context.saveOrThrow()
    }

    // MARK: - The clock

    /// Runs the rest this exercise asks for when a set is ticked, and stops it
    /// when one is taken back — a set taken back did not happen, so there is
    /// nothing to be resting from.
    private func restChanged(for exercise: PlannedExercise, isCompleted: Bool) {
        guard isCompleted else { return restTimer.stop() }
        guard hasWorkLeft else { return restTimer.stop() }
        guard let seconds = restPreferences.runningSeconds(
            prescribed: exercise.restSeconds, for: exercise.exerciseID
        ) else { return }
        restTimer.start(seconds: seconds, context: exercise.displayName)
    }

    /// Whether anything in this session is still waiting to be done.
    ///
    /// **Rest is the gap between two pieces of work, so the last set has no
    /// rest after it.** Ticking the last box started a countdown for nothing —
    /// a bar across the bottom of the screen telling a lifter who has finished
    /// to wait three minutes before the set that does not exist. What it is
    /// asking about is the whole session and not the exercise: rest between
    /// movements is real, so the clock still runs on the last set of the bench
    /// press when the rows are next.
    ///
    /// Warm-ups count as work left, because they are: a warm-up still waiting
    /// is a set he is about to do.
    private var hasWorkLeft: Bool {
        day.unloggedSetCount > 0
    }

    /// Runs a group's rest when a *round* closes, which is the one behavioural
    /// difference a group makes and the whole reason the grouping is worth
    /// expressing: ticking one movement starts nothing, because the next
    /// follows immediately.
    private func roundChanged(_ group: ExerciseGroup, completed: Bool) {
        guard completed, group.hasCompleteRound else { return restTimer.stop() }
        // The round that closes the session has nothing after it either.
        guard hasWorkLeft else { return restTimer.stop() }
        guard let key = group.restKey,
            let seconds = restPreferences.runningSeconds(
                prescribed: group.restSeconds, for: key)
        else { return }
        restTimer.start(seconds: seconds, context: group.title)
    }
}
