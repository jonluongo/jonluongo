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
    /// Whether the clock runs at all — one answer for the whole app, not for
    /// this exercise. See `RestPreferences.isClockOn`.
    let isClockOn: Bool
    var onChange: (LifterRest) -> Void
    var onClockSwitched: (Bool) -> Void

    @State private var minutes: Int
    @State private var seconds: Int
    @State private var isOn: Bool

    init(
        exerciseName: String, prescribedSeconds: Int?,
        rest: LifterRest, isClockOn: Bool,
        onChange: @escaping (LifterRest) -> Void,
        onClockSwitched: @escaping (Bool) -> Void
    ) {
        self.exerciseName = exerciseName
        self.prescribedSeconds = prescribedSeconds
        self.rest = rest
        self.isClockOn = isClockOn
        self.onChange = onChange
        self.onClockSwitched = onClockSwitched
        // The wheels open on whatever the clock would run right now — the
        // lifter's length if he set one, otherwise the prescribed one, and zero
        // when neither exists. Nothing is suggested: an app that opened this on
        // "90s" for an exercise nobody prescribed rest for would be making a
        // training decision with a wheel.
        let opening = rest.runningSeconds(prescribed: prescribedSeconds)
            ?? prescribedSeconds ?? 0
        _minutes = State(initialValue: opening / 60)
        _seconds = State(initialValue: opening % 60)
        _isOn = State(initialValue: isClockOn)
    }

    private var total: Int { minutes * 60 + seconds }

    /// Whether the lifter's clock differs from the plan — the only condition
    /// under which there is anything to put back.
    private var isOverridden: Bool { prescribedSeconds != nil && rest != .asPrescribed }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Panel {
                        Toggle("Rest timer", isOn: switchBinding)
                            .accessibilityHint("Turns the countdown on or off everywhere")
                            .font(.supersetBody)
                            // The one switch in the app, and it came up in the
                            // system's green — the second saturated colour in a
                            // one-accent palette, which is what a green Finish
                            // button was killed for. A switch on is a filled
                            // shape, which is exactly what the theme is for.
                            .tint(Palette.accent)
                        if isOn {
                            HStack(spacing: 0) {
                                wheel(selection: $minutes, unit: "min")
                                wheel(selection: $seconds, unit: "s")
                            }
                            .frame(maxHeight: 160)
                            .onChange(of: total) { _, newTotal in choose(newTotal) }
                        }
                    }
                    // What Claude asked for, under the control rather than
                    // wrapped in a panel of its own: it is a note about the
                    // thing above it, not a fact in its own right.
                    Text(prescriptionSentence).note()
                }

                if isOverridden {
                    Section {
                        // A word, not a slab. It was a full panel reading "Use
                        // Prescribed Rest" — a heading-length instruction on a
                        // white card, for the least consequential control in the
                        // app — and Jon asked for the opposite: *"maybe just
                        // make it a reset text no background."* The sentence
                        // above it already says what Claude prescribed, so this
                        // only has to say put it back.
                        PrimaryActionButton(title: "Reset", prominence: .quiet) {
                            usePrescribed()
                        }
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: PanelMetrics.inset,
                            bottom: 0, trailing: PanelMetrics.inset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            // The app's own list, not the system's grouped one. This was the
            // last screen still made of stock grey panels with stock corners,
            // which is what happens to a sheet nobody has looked at since the
            // rest of the app was redrawn.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        // Every other sheet in the app draws one. Without it this was the one
        // half-height sheet with no sign it could be pulled down.
        .presentationDragIndicator(.visible)
    }

    /// What Claude asked for, said plainly, together with the one thing the
    /// lifter needs to know about editing it: he is not editing it.
    private var prescriptionSentence: String {
        guard let prescribedSeconds else {
            return """
                No rest was prescribed here. A timer you set is your own — \
                it doesn't change the block.
                """
        }
        return """
            Your coach prescribed \(PrescriptionSummary.rest(prescribedSeconds) ?? "") here. \
            Changing the timer doesn't change the block.
            """
    }

    /// **The switch is the app's, not this exercise's.** A lifter reaching for
    /// it is not saying *not on the bench press*, he is saying *not today* —
    /// and having to say it again on the next movement is the app making him
    /// repeat himself. The wheels below it stay per exercise, because a length
    /// is the thing that genuinely differs between movements.
    private var switchBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                isOn = on
                onClockSwitched(on)
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
