import Foundation
import LiftingKit

/// What a prescribed rep target puts into a set the app creates, and what it
/// shows when it puts nothing.
///
/// Used by `ActiveWorkoutView` when it seeds a session's sets and by
/// `SetRowView` when it labels an empty rep field. The rule is the one the
/// whole app runs on: the prescription reaches the lifter unaltered, and
/// nothing else does. A target that names one number (`"5"`) is seeded as that
/// number. A target that names a range (`"8-12"`) names no single number, so
/// nothing is seeded and the range is shown as the target instead — picking an
/// end of a range would be the app deciding how hard to train, and picking
/// what the lifter happened to do last time would be it quietly dropping the
/// prescription altogether. Last session's performance belongs beside the
/// field as reference, never inside it.
///
/// A `nil` target is a set that stated no reps, which is the same as an empty
/// one and is answered the same way: nothing seeded, nothing shown.
///
/// Depends on: `RepRange` from LiftingKit.
enum RepPrescription {

    /// The rep count to seed into a new set, or `nil` when the prescription
    /// names no single number — a range, or no target at all.
    static func seededReps(for repRange: String?) -> Int? {
        let range = RepRange(repRange ?? "")
        guard !range.isEmpty, range.lowerBound == range.upperBound else { return nil }
        return range.lowerBound
    }

    /// What an empty rep field shows: the prescribed target exactly as the plan
    /// wrote it (`"8-12"`, `"AMRAP"`), and nothing at all when the plan named
    /// none. Never a number the app chose.
    ///
    /// It used to show `—` for an absent target, which put a mark inside a field
    /// whose job is to invite a number. A placeholder is a hint about what to
    /// type; a dash hints at nothing, and a fresh session drew two of them on
    /// every row, so a table waiting to be filled in read as a table that was
    /// broken. The column header says what the field holds. An empty field
    /// says the plan asked for no figure, which is the truth.
    static func targetText(for repRange: String?) -> String {
        (repRange ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same hint, with the unit taken off when the row already names it.
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
    static func targetFigure(for repRange: String?, measure: WorkMeasure) -> String {
        let written = targetText(for: repRange)
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

/// What a prescribed hold puts into a set the app creates, and which of the two
/// things a set can record it records.
///
/// **What it does.** Answers, for one prescription, whether the work is held
/// for time rather than counted (`isTimed`), and what a new row is seeded with
/// when it is (`seededSeconds`). It is `RepPrescription`'s mirror, and between
/// them a prescribed target reaches the lifter as the unit it was written in.
///
/// **How it is used.** `ActiveWorkoutView` asks `seededSeconds` when it lays a
/// session out. A hold whose text names one duration is seeded with it, exactly
/// as a rep target naming one number is; a range seeds nothing, because choosing
/// an end of it would be the app deciding how long to hold. Which of the three
/// things a row records is asked of `WorkPrescription`, not here.
///
/// **What it depends on.** `WorkDuration` from LiftingKit, which does the
/// reading. It decides nothing about training: an exercise is timed because its
/// prescription says so, never because of anything the lifter did.
enum HoldPrescription {

    /// Whether this target is work held for time rather than counted.
    static func isTimed(_ target: String?) -> Bool {
        WorkDuration(target ?? "").isTimed
    }

    /// The hold to seed into a new set, in seconds, or `nil` when the
    /// prescription names no single duration — a range, or no target at all.
    static func seededSeconds(for target: String?) -> Int? {
        WorkDuration(target ?? "").seconds
    }
}

/// Which of the things a set can record this exercise's rows record, and what a
/// carry seeds a new row with.
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
/// `ActiveWorkoutView` asks `seededDistance` when it lays a session out. A carry
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
}

/// How a prescribed effort is written on screen.
///
/// **What it does.** Turns an `IntensityTarget` into the phrase a lifter would
/// read — `"80% effort"`, `"2 RIR"`, `"80% 1RM"` — for the exercise header, the
/// set rows, and the session preview.
///
/// **RPE is written as a percentage of effort.** `RPE 8` is jargon standing for
/// a position on a ten-point scale, and the owner reads a percentage without
/// having to translate. The figure is the same figure: eight out of ten written
/// as eighty out of a hundred, which is a restatement rather than a conversion.
/// Nothing here maps an RPE onto a percentage of a maximum — that is a table
/// lookup depending on the rep count, a genuine training claim, and not
/// something this app would ever make.
///
/// **`% effort` and `% 1RM` are different sentences and both say `%`.** They are
/// distinguished by the word after the figure, and the second is never derived
/// from the first: `80% 1RM` appears only where Claude prescribed a percentage
/// of a maximum himself.
///
/// **How it is used.** Call `label(for:)` and draw the result; `nil` means the
/// plan named no target, and nothing is drawn rather than a placeholder
/// inviting the lifter to invent one.
///
/// **What it depends on.** `IntensityTarget` from LiftingKit. It formats and
/// nothing else: no scale is converted into another, no value is bounded or
/// rounded, and a scale this build has never heard of is shown as written
/// rather than dropped — which is the only honest thing to do with a target
/// somebody deliberately prescribed.
enum IntensityPrescription {

    /// The target as a phrase, or `nil` when there is none.
    static func label(for intensity: IntensityTarget?) -> String? {
        guard let intensity else { return nil }
        let value = intensity.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // A value that will not read as a number is not made into one. "RPE
        // 8-9" spans; "RPE top set" is not something to multiply, and is shown
        // as written rather than mangled into a figure nobody prescribed.
        if intensity.scale == .rpe {
            guard let percent = Self.effortPercent(value) else { return "RPE \(value)" }
            return "\(percent) effort"
        }
        if intensity.scale == .repsInReserve { return "\(value) RIR" }
        if intensity.scale == .percentOfOneRepMax {
            // "80" and "80%" both read as a percentage; neither gains a second
            // per-cent sign, and neither loses one it was written with.
            return value.hasSuffix("%") ? "\(value) 1RM" : "\(value)% 1RM"
        }
        // A scale nobody here has heard of is named and shown, in the words it
        // arrived in. Guessing at a phrasing for it would be inventing one.
        return "\(intensity.scale.rawValue) \(value)"
    }

    /// A point or a span on the ten-point scale, written out of a hundred —
    /// `"8"` as `"80%"`, `"7-8"` as `"70-80%"`, `"7.5"` as `"75%"`.
    ///
    /// `nil` when any part of it is not a number, which is the whole of the
    /// guard on this: a value the app cannot read is a value it must print as
    /// written rather than turn into a figure the plan does not contain.
    private static func effortPercent(_ value: String) -> String? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var written: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let rating = Double(trimmed) else { return nil }
            written.append((rating * 10).compactString)
        }
        return written.joined(separator: "-") + "%"
    }
}
