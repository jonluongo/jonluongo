import Foundation
import SwiftData
import LiftingKit

/// Everything logging a session *does*, as opposed to how it looks.
///
/// **What it does.** Owns the two jobs the logging screen was carrying besides
/// layout: writing to the record — recording a set, taking one back, adding one
/// nobody prescribed, finishing and un-finishing — and running the clock the
/// prescription asks for. Nothing here draws.
///
/// **Recording a set creates a row; taking it back deletes one.** It used to
/// flip `isCompleted` on a row seeded the moment the screen opened, which is why
/// the store held a set for everything the coach asked for whether or not it
/// ever happened, and why `reps` defaulted to zero. A performed row exists only
/// if the user performed it.
///
/// **How it is used.** `ActiveWorkoutView` builds one per redraw from the
/// context and the two environment objects it already holds, then calls it.
/// Every write is `throws`: a failed save is shown to the user by the view
/// that can show it, rather than being handled by a type with no way to say so.
///
/// **It decides nothing about training.** How long to rest is Claude's to
/// prescribe and the user's to override, in that order, and this only asks
/// `RestPreferences` which of the two answers applies. Where neither has said
/// anything, no clock starts: the app does not invent one.
///
/// **What it depends on.** `Session`, `PlannedExercise`, `PlannedSet` and
/// `PerformedSet` from Store, `ExerciseGroup` for a group's rounds, and the rest
/// timer and preferences it is handed.
@MainActor
struct SessionLog {

    let session: Session
    let context: ModelContext
    let restTimer: RestTimerModel
    let restPreferences: RestPreferences

    // MARK: - Writing to the record

    /// Records a set as performed, then runs the rest it asks for.
    ///
    /// **The write is the point.** A recorded set is the one irreversible thing
    /// a user does in this app — it is the claim that the work happened — so
    /// it is saved here rather than left to SwiftData's autosave, which does run
    /// but on no schedule anyone can promise.
    ///
    /// Which measure is written is decided by what was prescribed, never by what
    /// was typed: a hold cannot land in the rep column by a user tapping the
    /// wrong field.
    func record(
        _ slot: TrainingSlot, load: Mass? = nil, reps: Int? = nil,
        durationSeconds: Int? = nil, distance: Distance? = nil,
        at moment: Date = Date()
    ) throws {
        let performed = PerformedSet(
            setIndex: slot.planned.setIndex, isWarmup: slot.planned.isWarmup,
            load: load, reps: reps, durationSeconds: durationSeconds,
            distance: distance, completedAt: moment)
        performed.planned = slot.planned
        performed.exercise = performedExercise(for: slot.exercise, at: moment)
        context.insert(performed)

        restStarted(after: slot)
        try context.saveOrThrow()
    }

    /// Takes a set back out of the record, and stops any clock it started.
    ///
    /// A set taken back did not happen, so there is nothing to be resting from —
    /// and nothing left in the record either. The row on screen returns to being
    /// the prescription it always was.
    func takeBack(_ slot: TrainingSlot) throws {
        guard let performed = slot.record else { return }
        let exercise = performed.exercise
        context.delete(performed)
        // An exercise with nothing left performed against it is not a
        // performance. Leaving an empty one would put a session in the coach's
        // history that the user did not train.
        if let exercise, (exercise.sets ?? []).allSatisfy({ $0 === performed }) {
            context.delete(exercise)
        }
        restTimer.stop()
        try context.saveOrThrow()
    }

    /// A set the user did that nobody prescribed.
    ///
    /// It has no `PlannedSet` behind it, which is exactly what the nullable link
    /// is for. Nothing is invented for it: no load, no count, no target.
    func addSet(
        to exercise: PlannedExercise, warmup: Bool, at moment: Date = Date()
    ) throws {
        let performance = performedExercise(for: exercise, at: moment)
        let performed = PerformedSet(
            setIndex: (performance.sets ?? []).count, isWarmup: warmup, completedAt: moment)
        performed.exercise = performance
        context.insert(performed)
        try context.saveOrThrow()
    }

    /// Writes what the user has to say about a movement today.
    ///
    /// **It creates the performance if he has not logged a set yet.** His words
    /// are a record of the session as much as a ticked box is, and a note he
    /// wrote before his first set would otherwise have nowhere to go. Clearing
    /// it back to nothing leaves an empty performance behind only if he has
    /// logged sets against it; one holding neither is deleted, because an empty
    /// performance would put a session in the coach's history he did not train.
    func writeNote(_ note: String?, for exercise: PlannedExercise) throws {
        let text = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (session.performedExercises ?? []).first { $0.planned === exercise }

        if let text, !text.isEmpty {
            let performance = existing ?? performedExercise(for: exercise, at: Date())
            performance.userNote = text
        } else if let existing {
            existing.userNote = nil
            if (existing.sets ?? []).isEmpty { context.delete(existing) }
        }
        try context.saveOrThrow()
    }

    /// Marks the session trained. The first finish stamps the time and a later
    /// one leaves it: when he trained is a fact, and re-finishing a corrected
    /// session does not move it.
    func finish() throws {
        restTimer.stop()
        if session.finishedAt == nil {
            session.finishedAt = Date()
        }
        try context.saveOrThrow()
    }

    /// Takes a finished session back to unfinished, which is what makes
    /// reopening one mean anything.
    func unfinish() throws {
        session.finishedAt = nil
        try context.saveOrThrow()
    }

    /// Turns the countdown on or off everywhere, and stops the one running.
    ///
    /// **The switch has to silence the clock that is already going.** It only
    /// wrote the preference, so a user reaching for it mid-rest — which is
    /// when anyone reaches for it — kept the bar counting and kept the alerts
    /// armed. Off means off now, not from the next set.
    func clockSwitched(_ isOn: Bool) {
        restPreferences.setClockIsOn(isOn)
        if !isOn { restTimer.stop() }
    }

    // MARK: - The clock

    /// Runs whatever rest follows the set just recorded.
    ///
    /// Inside a group the clock waits for the *round*: performing one movement
    /// starts nothing, because the next follows immediately. That is the one
    /// behavioural difference a group makes, and the whole reason the grouping
    /// is worth expressing.
    private func restStarted(after slot: TrainingSlot) {
        // **Rest is the gap between two pieces of work, so the last set has no
        // rest after it.** Recording the last box used to start a countdown for
        // nothing — a bar telling a user who has finished to wait three
        // minutes for the set that does not exist.
        guard hasWorkLeft else { return restTimer.stop() }

        guard let group = groupContaining(slot.exercise) else {
            guard let seconds = restPreferences.runningSeconds(
                prescribed: slot.exercise.restSeconds, for: slot.exercise.exerciseID)
            else { return restTimer.stop() }
            return restTimer.start(seconds: seconds, context: name(of: slot.exercise))
        }

        guard group.isRoundComplete(at: slot.workingNumber - 1) else { return restTimer.stop() }
        guard let key = group.restKey,
            let seconds = restPreferences.runningSeconds(
                prescribed: group.restSeconds, for: key)
        else { return restTimer.stop() }
        restTimer.start(seconds: seconds, context: "Round \(group.letter)")
    }

    /// Whether anything in this session is still waiting to be done.
    ///
    /// It asks about the whole session rather than the exercise: rest between
    /// movements is real, so the clock still runs after the last set of the
    /// bench press when the rows are next. Warm-ups count as work left, because
    /// they are — one still waiting is a set he is about to do.
    private var hasWorkLeft: Bool {
        session.orderedExercises
            .flatMap(\.orderedSets)
            .contains { !$0.hasBeenPerformed }
    }

    private func groupContaining(_ exercise: PlannedExercise) -> ExerciseGroup? {
        SessionGrouping.entries(of: session.orderedExercises)
            .compactMap { $0.groupContaining(exercise) }
            .first
    }

    // MARK: - Finding the performance to hang a set on

    /// The performance of this movement in this session, made if it is the first
    /// set of it.
    ///
    /// One row per exercise per day is the grain the coach reads at, so a second
    /// set of the same movement joins the performance already there rather than
    /// starting another.
    private func performedExercise(
        for exercise: PlannedExercise, at moment: Date
    ) -> PerformedExercise {
        if let existing = (session.performedExercises ?? []).first(where: { $0.planned === exercise }
        ) {
            return existing
        }
        let performance = PerformedExercise(
            exerciseID: exercise.exerciseID, occurredAt: moment, source: .logged)
        performance.session = session
        performance.planned = exercise
        context.insert(performance)
        return performance
    }

    /// What to call a movement on the clock. The catalog owns the name, and this
    /// only has the key — the view resolves it, so the fallback here is the key
    /// itself rather than a blank.
    private func name(of exercise: PlannedExercise) -> String {
        exercise.exerciseID.rawValue
    }
}
