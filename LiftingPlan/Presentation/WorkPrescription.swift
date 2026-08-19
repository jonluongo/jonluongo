import Foundation
import LiftingKit

/// Which of the things a set can record this exercise's rows record, what a
/// carry seeds a new row with, and what an empty work field hints.
///
/// **What it does.** Gives one answer for a whole exercise — counted, held, or
/// carried over a distance in a stated unit — and reads the distance a carry
/// prescribes. It is the third of the three seams that read a prescription, and
/// deliberately the only one that answers *which*: a set that could be described
/// as timed by one question and as carried by another is a set logged wrong, so
/// there is exactly one question and it has exactly one answer.
///
/// **How it is used.** `ExerciseLogSection` asks `measure(of:)` to label the
/// column and to bind every row under it to the field that measure names;
/// `ActiveWorkoutView` asks `seededDistance` when it lays a session out, and
/// `targetFigure` is what an empty field in that column offers. A carry
/// naming one distance is seeded with it, exactly as a rep target naming one
/// number is; a range seeds nothing, because choosing an end of it would be the
/// app deciding how far to carry.
///
/// **What it depends on.** `WorkMeasure` and `WorkDistance` from LiftingKit,
/// which do the reading, and `PlannedExercise` for the whole-exercise question.
/// It decides nothing about training: an exercise is a carry because its
/// prescription says so, never because of anything the lifter did.
enum WorkPrescription {

    /// What this exercise's work is measured in.
    ///
    /// One answer for the whole exercise, because the column above the set table
    /// is one word and it must not lie about the rows under it. An exercise is
    /// measured by its own target when that target names a measure, and
    /// otherwise by the first of its sets that names one — which is what a plank
    /// prescribed as three thirty-second holds, or a carry prescribed as three
    /// listed distances, looks like from either direction.
    static func measure(of exercise: PlannedExercise) -> WorkMeasure {
        let own = WorkMeasure(exercise.repRange)
        guard own == .repetitions else { return own }
        return exercise.prescribedSets
            .lazy
            .map { WorkMeasure($0.repRange ?? "") }
            .first { $0 != .repetitions } ?? .repetitions
    }

    /// The distance to seed into a new set, or `nil` when the prescription names
    /// no single distance — a range, a unit this build cannot read, or no target
    /// at all.
    static func seededDistance(for target: String?) -> Distance? {
        WorkDistance(target ?? "").distance
    }

    /// What an empty work field hints, with the unit taken off when the row
    /// already draws it.
    ///
    /// A counted row shows the target as written — `"8-12"`, `"AMRAP"` — because
    /// the `×` beside it is all the unit it has. A hold and a carry are
    /// different: the row draws `s` or `m` after the field, so a placeholder
    /// reading `45 seconds` says the unit twice and, in a field sized for three
    /// figures, says it as `45 sec…`. The figure alone is the hint; the suffix
    /// is the unit.
    ///
    /// Read through `WorkDuration` and `WorkDistance` rather than by trimming
    /// words off the string, so `"1:30"` becomes `90` and `"30-45 seconds"`
    /// becomes `30-45` — and so this cannot disagree with the readers that
    /// decided what the row records in the first place. A prescription those
    /// readers cannot parse falls back to what the plan wrote, which is still
    /// better than nothing.
    static func targetFigure(for target: String?, measure: WorkMeasure) -> String {
        let written = RepPrescription.targetText(for: target)
        switch measure {
        case .repetitions:
            return written
        case .time:
            let held = WorkDuration(written)
            guard !held.isEmpty else { return written }
            return held.lowerSeconds == held.upperSeconds
                ? "\(held.lowerSeconds)"
                : "\(held.lowerSeconds)-\(held.upperSeconds)"
        case .distance:
            let carried = WorkDistance(written)
            guard !carried.isEmpty else { return written }
            return carried.lowerValue == carried.upperValue
                ? carried.lowerValue.compactString
                : "\(carried.lowerValue.compactString)-\(carried.upperValue.compactString)"
        }
    }
}
