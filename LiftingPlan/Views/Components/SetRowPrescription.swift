import Foundation
import LiftingKit

/// What one row of a set table is shown besides the two numbers the lifter
/// types: what the plan asked of that set, and what he did on it last time.
///
/// **What it does.** Answers the four questions a row asks — what this exercise's
/// work is measured in, what the plan prescribed for *this* set, what an empty
/// weight field should show, and what the previous session recorded. Each is
/// per set rather than per exercise, so a ramp shows the load of the set being
/// logged rather than one figure standing in for all of them.
///
/// **How it is used.** `ExerciseLogSection` builds one per exercise and
/// `SupersetLogSection` one per member of a group, then asks it for each row.
/// One type rather than two copies of these rules, so a row inside a group and a
/// row on its own cannot come to read a prescription differently.
///
/// **What it depends on.** `WorkPrescription` and `PerformanceHistory` for the
/// readings, `PlannedExercise` and `TrainingPlan` from Store, and `MassUnit`
/// from LiftingKit. It writes nothing and invents nothing: an absent
/// prescription stays absent, which in a field is an empty field and in the
/// column that reports the last session is `—`.
struct SetRowPrescription {

    let exercise: PlannedExercise
    /// Every block, for the one question that reaches outside this session:
    /// what he did on this movement last time.
    let plans: [TrainingPlan]
    /// The lifter's display unit, which a prescribed load is converted into for
    /// display and nothing else.
    let unit: MassUnit

    /// What this exercise's work is measured in — reps, seconds, or a distance
    /// in the unit it was prescribed in. It comes from the prescription and
    /// nothing else.
    var measure: WorkMeasure { WorkPrescription.measure(of: exercise) }

    /// Every set the plan prescribed, in order and stated in full.
    var prescribedSets: [SetPrescription] { exercise.prescribedSets }

    /// What the plan asked of the working set at `workingNumber`, or `nil` when
    /// it asked for nothing about it — a warmup, or a set the lifter added past
    /// the ones prescribed. Nothing is stretched to cover an extra set: a fourth
    /// row under a three-set prescription is his own, not the plan's.
    func prescription(forWorkingNumber workingNumber: Int, isWarmup: Bool) -> SetPrescription? {
        guard !isWarmup, prescribedSets.indices.contains(workingNumber - 1) else { return nil }
        return prescribedSets[workingNumber - 1]
    }

    /// What an empty weight field shows: the load this set was prescribed, in
    /// the lifter's display unit, and nothing when none was. A placeholder
    /// rather than a value, so the prescription reaches him without the app
    /// claiming he lifted it.
    ///
    /// Empty rather than `—`, which is the mark this type uses for a *reading*
    /// that does not exist. Inside a field it was neither: a placeholder is a
    /// hint about what to type, and a dash hints at nothing while making a
    /// fresh table look broken. `previousText` keeps the dash, because that
    /// column is read rather than typed into and a lift with no history genuinely
    /// has nothing to report.
    func loadTarget(_ prescription: SetPrescription?) -> String {
        guard let load = prescription?.suggestedLoad else { return "" }
        return load.converted(to: unit).value.compactString
    }

    /// What he did on this set last time, in the unit he did it in. A hold is
    /// reported as the seconds it was held and a carry as the distance it
    /// covered; nothing here converts one measure into another, because they are
    /// not the same measurement.
    func previousText(workingIndex: Int, isWarmup: Bool) -> String {
        guard !isWarmup, workingIndex >= 0 else { return "—" }
        let previous = PerformanceHistory.latestHistory(
            for: exercise.exerciseID, excluding: exercise, from: plans
        )?.recentSets ?? []
        guard workingIndex < previous.count else { return "—" }
        let record = previous[workingIndex]
        let measured = record.durationSeconds.map { "\($0)s" } ?? record.distance?.description
        let work = measured ?? "\(record.reps)"
        if let load = record.load?.converted(to: unit), load.value > 0 {
            return "\(load.value.compactString) × \(work)"
        }
        return measured != nil ? work : "\(work) reps"
    }
}
