import Foundation
import LiftingKit

/// How a prescription is written on screen.
///
/// **What it does.** Says what an exercise asks for above its table, and what
/// one set asks that the table has not already shown. It absorbed
/// `IntensityPrescription` and `RestPrescription`, each of which had a single
/// caller and existed to format one field.
///
/// **What it depends on.** `IntensityTarget` and `Target` from LiftingKit, and
/// `PlannedExercise` from Store. It writes nothing and invents nothing.
enum PrescriptionSummary {

    /// The effort this exercise asks for, when it asks the same of every set.
    ///
    /// **Stated once above the table rather than on every row.** Where the sets
    /// ask for different efforts each row states its own, and there is nothing
    /// left here to add.
    ///
    /// `nil` when the table says everything, which is the ordinary case.
    static func aboveTable(for exercise: PlannedExercise) -> String? {
        guard statesOneEffortThroughout(exercise) else { return nil }
        return label(for: exercise.orderedSets.first?.intensity)
    }

    /// What one prescribed set asks that the row has not already shown.
    ///
    /// The load and the target are left out on purpose: they are already in
    /// front of the user as the placeholders in that row's two fields, and a
    /// line repeating them would be the screen saying the same thing twice.
    ///
    /// **A set with a load prescribed is not shown its intensity.** The
    /// intensity is already baked into the number on the bar — a coach who
    /// writes 100 kg for five has done the reasoning an RPE is shorthand for,
    /// and printing both under every row is showing his working. Where no load
    /// was prescribed the intensity *is* the prescription: "work up to a top
    /// single at RPE 8" leaves the user nothing else to go on.
    ///
    /// It is left out again when every set asks the same effort, because the
    /// line above the table stated it once for all of them.
    static func detail(for set: PlannedSet, in exercise: PlannedExercise) -> String? {
        guard set.load == nil, !statesOneEffortThroughout(exercise) else { return nil }
        return label(for: set.intensity)
    }

    /// How hard, on whatever scale the coach works in — `RPE 8`, `2 RIR`,
    /// `80% 1RM`. Carried as written and never converted: two RIR is not eight
    /// RPE unless a coach says so.
    ///
    /// `nil` when none was stated, which is not a zero and not a default.
    static func label(for intensity: IntensityTarget?) -> String? {
        guard let intensity, !intensity.value.isEmpty else { return nil }
        switch intensity.scale {
        case .rpe: return "RPE \(intensity.value)"
        case .repsInReserve: return "\(intensity.value) RIR"
        case .percentOfOneRepMax: return "\(intensity.value)% 1RM"
        default: return "\(intensity.value) \(intensity.scale.rawValue)"
        }
    }

    /// How long to rest, written for the user — `2:00`, `90s`.
    ///
    /// `nil` when the coach prescribed none, which is why the line appears on
    /// some exercises and not others rather than reading `Rest —`.
    static func rest(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0
            ? "\(minutes):00"
            : String(format: "%d:%02d", minutes, remainder)
    }

    /// Whether every set of this exercise asks for the same effort.
    ///
    /// A ramp's top single and a drop set's last set ask for something of their
    /// own, and that is what puts the effort back on the rows.
    private static func statesOneEffortThroughout(_ exercise: PlannedExercise) -> Bool {
        let efforts = exercise.workingSets.map(\.intensity)
        guard let first = efforts.first, first != nil else { return false }
        return efforts.allSatisfy { $0 == first }
    }
}
