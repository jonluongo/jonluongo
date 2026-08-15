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
struct SetRowView: View {
    @Bindable var set: LoggedSet
    /// 1-based working-set number, ignored when the row is a warmup.
    var workingNumber: Int
    var previousText: String
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

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps > 0 ? String(set.reps) : "" },
            set: { set.reps = Int($0.filter(\.isNumber)) ?? 0 }
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

            field(text: weightText, placeholder: "—", isDecimal: true)
            field(text: repsText, placeholder: "0", isDecimal: false)

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
