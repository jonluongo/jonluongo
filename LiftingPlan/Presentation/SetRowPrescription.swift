import Foundation
import LiftingKit

/// What one row of a set table shows besides the two numbers the user types.
///
/// **What it does.** Turns a row's prescription into the two placeholders in
/// front of him: what to put on the bar, and what to do with it.
///
/// **A row is its prescription, so there is nothing to look up.** This used to
/// take a working number and find the matching entry in a derived list, because
/// a row was a seeded record and the prescription was reconstructed beside it.
/// A row is a `PlannedSet` now; `TrainingSlot` carries it, and the mapping is
/// gone.
///
/// **Nothing is converted.** A load is drawn in the unit it was prescribed in,
/// exactly as `Mass` keeps it — the display unit that used to convert here was a
/// fact about the user, and it lives in `ACCOUNT.md` with the rest of him.
///
/// **A placeholder is never a value.** The prescription reaches him without the
/// app claiming he lifted it, and nothing is logged until he types.
///
/// **What it depends on.** `Target` and `Mass` from LiftingKit, `TrainingSlot`,
/// and one previous performance. It writes nothing: an absent prescription stays
/// absent, which in a field is an empty field.
struct SetRowPrescription {

    let slot: TrainingSlot
    /// What he did on this movement last time, for the one field a prescription
    /// may leave blank. `nil` the first time.
    let previous: SnapshotPerformedExercise?

    /// What this row's work is measured in — counted, held, or carried. It comes
    /// from the prescription and nothing else, never from what was typed.
    ///
    /// A row the coach set no target for is counted, which is what the field has
    /// always been and what the row is drawn beside. **A row he added has no
    /// prescription at all** and is counted for the same reason: reps is what a
    /// set is measured in unless something says otherwise, and on an added row
    /// nothing does.
    var measure: WorkMeasure { slot.planned?.target?.measure ?? .repetitions }

    /// What the empty weight field shows: the load this set was prescribed, and
    /// nothing when none was.
    ///
    /// Empty rather than a dash: a placeholder is a hint about what to type, and
    /// a dash hints at nothing while making a fresh table look broken.
    var loadPlaceholder: String {
        if let load = slot.planned?.load { return load.value.compactString }
        if let hint = lastLoadThisSession { return hint }
        return previousLoad
    }

    /// What the empty work field shows: the target as the coach wrote it —
    /// `8-12`, `45s`, `40m`, `AMRAP`.
    var workPlaceholder: String {
        if let target = slot.planned?.target { return target.shorthand }
        return lastRepsThisSession
    }

    /// What he last put on the bar for this movement *today*, for a row nobody
    /// prescribed.
    ///
    /// **An added row had no value and no placeholder, so it read as blank space
    /// rather than as a field.** He could type into it — editing a recorded row
    /// commits — but nothing on screen said so, which is a control that works
    /// and cannot be found.
    ///
    /// The last set of the same movement is the number he would have looked up:
    /// an extra set is nearly always the set he just did again. It is a hint and
    /// never a value — nothing is written until he types — which is the same
    /// rule `previousLoad` follows for a prescription that named no load.
    private var lastRecordedThisSession: PerformedSet? {
        (slot.exercise.performed ?? [])
            .flatMap { $0.sets ?? [] }
            .filter { $0.completedAt < (slot.record?.completedAt ?? .distantFuture) }
            .max { $0.completedAt < $1.completedAt }
    }

    private var lastLoadThisSession: String? {
        guard slot.planned == nil, let load = lastRecordedThisSession?.load, load.value > 0
        else { return nil }
        return load.value.compactString
    }

    private var lastRepsThisSession: String {
        guard slot.planned == nil, let last = lastRecordedThisSession else { return "" }
        return SetEntry.workText(of: last, measure: .repetitions)
    }

    /// What he put on the bar for this set last time, where the coach named no
    /// load.
    ///
    /// **The prescription always wins.** This fills a field that would otherwise
    /// be blank, with the one number a user would have looked up anyway. It is
    /// asked only where nothing was prescribed, so it never stands in front of a
    /// figure the coach wrote.
    private var previousLoad: String {
        guard !slot.isWarmup, let previous else { return "" }
        let index = slot.workingNumber - 1
        guard previous.sets.indices.contains(index),
            let load = previous.sets[index].load, load.value > 0
        else { return "" }
        return load.value.compactString
    }
}
