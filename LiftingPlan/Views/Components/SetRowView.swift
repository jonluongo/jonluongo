import SwiftUI
import SwiftData
import LiftingKit

/// One editable set row: a set badge, the previous session's result, inline
/// weight and reps fields, and a check to complete it (which starts the rest
/// timer). Row tint for the completed state is applied by the enclosing list.
///
/// Weight is entered and displayed in `unit` (the lifter's `profile.displayUnit`)
/// regardless of what unit `set.load` was originally logged in — the field
/// always shows/writes a value converted to `unit`, so switching units in
/// Settings doesn't strand a row showing the wrong number.
///
/// **The second field records what the plan prescribed, in the unit it
/// prescribed it in.** For counted work it writes `set.reps`; for a hold —
/// `isTimed` — it writes `set.durationSeconds` instead, and the reps stay zero.
/// The number the lifter types under a placeholder reading "30 seconds" is
/// thirty-four *seconds*, and writing it into a rep count is how a plank became
/// thirty-four repetitions in every report that followed.
struct SetRowView: View {
    @Bindable var set: LoggedSet
    /// 1-based working-set number, ignored when the row is a warmup.
    var workingNumber: Int
    var previousText: String
    /// The target the plan prescribed *for this set*, shown in the second field
    /// while it is empty — `"8-12"`, `"AMRAP"`, `"30 seconds"`, or `"—"` when
    /// the plan named none. It is a placeholder rather than a value so the
    /// prescription reaches the lifter without the app claiming he lifted it.
    /// Sets of one exercise may carry different targets: a ramp and a drop set
    /// are exactly that.
    var repTargetText: String
    /// The load the plan prescribed for this set, shown the same way and for
    /// the same reason. `"—"` when it prescribed none.
    var loadTargetText: String
    /// Whether this row records a hold rather than a rep count. Decided by the
    /// prescription, in `HoldPrescription`, and never by what is typed.
    var isTimed: Bool
    var unit: MassUnit
    var onComplete: () -> Void

    private var weightText: Binding<String> {
        Binding(
            get: { set.load.map { $0.converted(to: unit).value.compactString } ?? "" },
            set: { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
                    set.load = nil
                    return
                }
                set.load = Mass(value: value, unit: unit)
            }
        )
    }

    /// The second field's text, bound to whichever of the two things this row
    /// records. Nothing is ever written to both: a row is counted or it is
    /// held.
    private var workText: Binding<String> {
        isTimed ? durationText : repsText
    }

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps > 0 ? String(set.reps) : "" },
            set: { set.reps = Int($0.filter(\.isNumber)) ?? 0 }
        )
    }

    /// A hold, in seconds. Cleared to `nil` rather than to zero when the field
    /// is emptied — a set that was not timed did not last no time.
    private var durationText: Binding<String> {
        Binding(
            get: { set.durationSeconds.map(String.init) ?? "" },
            set: { set.durationSeconds = Int($0.filter(\.isNumber)) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set badge — tap to toggle warmup.
            Button {
                set.isWarmup.toggle()
            } label: {
                Text(set.isWarmup ? "W" : "\(workingNumber)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(set.isWarmup ? .orange : .primary)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)

            Text(previousText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            field(text: weightText, placeholder: loadTargetText, isDecimal: true)
            field(text: workText, placeholder: repTargetText, isDecimal: false)

            Button {
                complete()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted ? .green : .secondary)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func field(text: Binding<String>, placeholder: String, isDecimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(isDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            // A prescribed target like "8-12" is wider than a logged number;
            // shrink it rather than truncate the prescription.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 62, height: 34)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
    }

    private func complete() {
        let wasCompleted = set.isCompleted
        set.isCompleted.toggle()
        if set.isCompleted {
            set.completedAt = Date()
            if !wasCompleted { onComplete() }
        }
    }
}
