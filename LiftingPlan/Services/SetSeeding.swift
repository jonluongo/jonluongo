import Foundation
import SwiftData
import LiftingKit

/// The rows a logging screen starts with, and the row an added set becomes.
///
/// **What it does.** Builds `LoggedSet`s from what the plan prescribed and
/// inserts them. Every number it writes comes from the prescription or from the
/// set the lifter just logged; none of it comes from a rule of the app's, and
/// none of it comes from what he did last session — last session is shown beside
/// each row as reference, and substituting it for the prescription is how the
/// prescription stops reaching him at all.
///
/// **How it is used.** `ActiveWorkoutView` calls `seedMissingSets` when it
/// opens and `addSet` when the lifter asks for another row, then saves. It lives
/// beside `RepPrescription`, `HoldPrescription` and `WorkPrescription` because
/// it is built entirely out of them — reading a prescription into a field is
/// their job, and this is the one caller that writes the result down.
///
/// **What it depends on.** The three prescription readers, `PlannedExercise`
/// and `LoggedSet` from Store, and a `ModelContext` to insert into. It saves
/// nothing itself: the screen owns the save, because the screen is what has to
/// show the lifter when one fails.
enum SetSeeding {

    /// Pre-populates each exercise with exactly the sets it prescribes, primed
    /// with what the plan prescribed and nothing else.
    ///
    /// **Each row is seeded from its own set's prescription, not the exercise's
    /// average.** A ramp seeds 60, 70, 80 and a drop set seeds the lighter
    /// fourth row, because that is what was written; collapsing them into one
    /// figure would hand the lifter a session nobody prescribed. The seeded reps
    /// come from `RepPrescription`, which fills the field only when that set
    /// named one number and leaves it blank — with the prescribed target shown
    /// in its place — when it named a range. Work prescribed as a hold seeds its
    /// seconds through `HoldPrescription` instead and leaves the reps at zero,
    /// so a thirty-second plank is logged as a thirty-second hold rather than as
    /// thirty repetitions; work prescribed as a carry seeds its distance through
    /// `WorkPrescription` for the same reason. Every seeded number is editable,
    /// because what gets logged is what he actually lifts.
    ///
    /// An exercise that already has rows is left alone.
    static func seedMissingSets(for exercises: [PlannedExercise], in context: ModelContext) {
        for exercise in exercises where (exercise.loggedSets ?? []).isEmpty {
            for (index, prescribed) in exercise.prescribedSets.enumerated() {
                let set = LoggedSet(
                    setIndex: index,
                    load: prescribed.suggestedLoad,
                    reps: RepPrescription.seededReps(for: prescribed.repRange) ?? 0,
                    // A hold seeds the seconds it prescribes and a carry the
                    // distance, each leaving the reps at zero. Only one of the
                    // three is ever filled in, because a set is counted, held,
                    // or carried, and never two of them at once.
                    durationSeconds: HoldPrescription.seededSeconds(for: prescribed.repRange),
                    distance: WorkPrescription.seededDistance(for: prescribed.repRange),
                    isWarmup: false
                )
                context.insert(set)
                set.exercise = exercise
            }
        }
    }

    /// Adds one more row to an exercise, working or warmup.
    ///
    /// An added working set copies the one just logged — the lifter's own
    /// number, in this session. When there is none to copy it falls back to the
    /// prescription, never to a rule of the app's. A hold copies the hold and a
    /// carry the distance, each with no reps, because those are the things a set
    /// can be and this one is the same kind as the one before it. A warmup
    /// copies nothing: it is not the work.
    static func addSet(to exercise: PlannedExercise, warmup: Bool, in context: ModelContext) {
        let existing = exercise.loggedSets ?? []
        let nextIndex = (existing.map(\.setIndex).max() ?? -1) + 1
        let ordered = existing.sorted { $0.setIndex < $1.setIndex }
        let template = ordered.last(where: { !$0.isWarmup })
        let set = LoggedSet(
            setIndex: nextIndex,
            load: warmup ? nil : template?.load,
            reps: warmup ? 0 : (template?.reps ?? RepPrescription.seededReps(for: exercise.repRange) ?? 0),
            durationSeconds: warmup
                ? nil
                : (template?.durationSeconds
                    ?? HoldPrescription.seededSeconds(for: exercise.repRange)),
            distance: warmup
                ? nil
                : (template?.distance
                    ?? WorkPrescription.seededDistance(for: exercise.repRange)),
            isWarmup: warmup
        )
        context.insert(set)
        set.exercise = exercise
    }
}
