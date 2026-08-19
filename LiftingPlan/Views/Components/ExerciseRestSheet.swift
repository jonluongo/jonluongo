import SwiftUI
import LiftingKit

/// One exercise's rest clock: on or off, and how long.
///
/// **What it does.** Edits what the *clock* does after a set of this exercise.
/// It states what Claude prescribed and leaves it exactly as written — the
/// prescription is not a field on this sheet and cannot be reached from it. A
/// rest menu that wrote straight to `PlannedExercise.restSeconds` is the bug
/// this replaces: a tap between sets rewrote the plan inside the record Claude
/// reads back to judge whether the plan is working.
///
/// **How it is used.** Presented from the rest line at the top of an exercise's
/// card on the logging screen, and from that exercise's menu. It is handed what
/// the plan prescribed and what the lifter has chosen so far, and calls
/// `onChange` with each new choice — saved as it is made, like the unit picker,
/// because there is no Done button to wait for.
///
/// **What it depends on.** `LifterRest` from Services and `RestPrescription`
/// for the words. It holds no model and writes nothing itself.
struct ExerciseRestSheet: View {

    /// The exercise being edited, named so the lifter can see which of them
    /// this is — they are all different, which is why the control moved here.
    let exerciseName: String
    /// What the plan prescribed, in seconds. Read-only, and shown as Claude's.
    let prescribedSeconds: Int?
    /// What the lifter has chosen for this exercise up to now.
    let rest: LifterRest
    var onChange: (LifterRest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var isOn: Bool

    init(
        exerciseName: String, prescribedSeconds: Int?,
        rest: LifterRest, onChange: @escaping (LifterRest) -> Void
    ) {
        self.exerciseName = exerciseName
        self.prescribedSeconds = prescribedSeconds
        self.rest = rest
        self.onChange = onChange
        // The wheels open on whatever the clock would run right now — the
        // lifter's length if he set one, otherwise the prescribed one, and zero
        // when neither exists. Nothing is suggested: an app that opened this on
        // "90s" for an exercise nobody prescribed rest for would be making a
        // training decision with a wheel.
        let opening = rest.runningSeconds(prescribed: prescribedSeconds)
            ?? prescribedSeconds ?? 0
        _minutes = State(initialValue: opening / 60)
        _seconds = State(initialValue: opening % 60)
        _isOn = State(initialValue: rest != .off)
    }

    private var total: Int { minutes * 60 + seconds }

    /// Whether the lifter's clock differs from the plan — the only condition
    /// under which there is anything to put back.
    private var isOverridden: Bool { prescribedSeconds != nil && rest != .asPrescribed }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Rest timer", isOn: switchBinding)
                    if isOn {
                        HStack(spacing: 0) {
                            wheel(selection: $minutes, unit: "min")
                            wheel(selection: $seconds, unit: "s")
                        }
                        .frame(maxHeight: 160)
                        .onChange(of: total) { _, newTotal in choose(newTotal) }
                    }
                } footer: {
                    Text(prescriptionSentence)
                }

                if isOverridden {
                    Section {
                        Button("Use Prescribed Rest") { usePrescribed() }
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// What Claude asked for, said plainly, together with the one thing the
    /// lifter needs to know about editing it: he is not editing it.
    private var prescriptionSentence: String {
        guard let prescribedSeconds else {
            return """
                Claude prescribed no rest here. A timer you set is your own — \
                it doesn't change the block.
                """
        }
        return """
            Claude prescribed \(RestPrescription.durationText(prescribedSeconds)) here. \
            Changing the timer doesn't change the block.
            """
    }

    /// The per-exercise switch. Off is a choice about this exercise; on gives
    /// the plan back when there is one to give back, and otherwise leaves the
    /// wheels where they stand.
    private var switchBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                isOn = on
                guard on else {
                    onChange(.off)
                    return
                }
                choose(total)
            }
        )
    }

    /// Records a length as what it means: the plan's own number is following
    /// the plan, not a choice that happens to match it, so a later change by
    /// Claude still reaches the lifter.
    private func choose(_ seconds: Int) {
        onChange(seconds == prescribedSeconds ? .asPrescribed : .seconds(seconds))
    }

    private func usePrescribed() {
        guard let prescribedSeconds else { return }
        minutes = prescribedSeconds / 60
        seconds = prescribedSeconds % 60
        isOn = true
        onChange(.asPrescribed)
    }

    /// A minutes or seconds wheel. Both run the full 0–59 of a clock face: the
    /// bounds come from how time is written, not from a view about how long a
    /// set is worth resting.
    private func wheel(selection: Binding<Int>, unit: String) -> some View {
        Picker(unit, selection: selection) {
            ForEach(0...59, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .accessibilityLabel(unit == "min" ? "Minutes" : "Seconds")
    }
}
