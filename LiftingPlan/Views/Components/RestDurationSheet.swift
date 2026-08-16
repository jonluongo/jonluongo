import SwiftUI

/// Runs a rest timer for however long the lifter wants, for this session only.
///
/// Presented from `ActiveWorkoutView`'s timer button and calls `onStart` with a
/// duration in seconds; the caller hands that straight to `RestTimerModel`.
///
/// **It never writes to the store.** The rest a plan prescribes is Claude's
/// and stays exactly as written — a timer the lifter runs between sets is a
/// stopwatch, not an edit to the prescription, and the record Claude reads back
/// has to be the plan he wrote. It also suggests nothing: the two wheels are a
/// clock, so every duration is equally available and none is put forward as the
/// right one.
///
/// Depends on: SwiftUI and `RestPrescription`.
struct RestDurationSheet: View {

    /// The duration the wheels start on — the last one the lifter ran this
    /// session, so running the same rest again is one tap.
    var initialSeconds: Int
    var onStart: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var seconds: Int

    init(initialSeconds: Int, onStart: @escaping (Int) -> Void) {
        self.initialSeconds = initialSeconds
        self.onStart = onStart
        _minutes = State(initialValue: initialSeconds / 60)
        _seconds = State(initialValue: initialSeconds % 60)
    }

    private var total: Int { minutes * 60 + seconds }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 0) {
                    wheel(selection: $minutes, unit: "min")
                    wheel(selection: $seconds, unit: "s")
                }
                .frame(maxHeight: 180)

                Button {
                    onStart(total)
                    dismiss()
                } label: {
                    Label("Start \(RestPrescription.durationText(total))", systemImage: "timer")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(total == 0)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// A minutes or seconds wheel. Both run the full 0–59 of a clock face:
    /// the bounds come from how time is written, not from a view about how
    /// long a set is worth resting.
    private func wheel(selection: Binding<Int>, unit: String) -> some View {
        Picker(unit, selection: selection) {
            ForEach(0...59, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }
}
