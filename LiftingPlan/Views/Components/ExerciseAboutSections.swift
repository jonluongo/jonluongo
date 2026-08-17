import SwiftUI
import LiftingKit

/// What a movement is, drawn as the top of its screen: where its demonstration
/// will play, what the catalog states about it, and how it is performed.
///
/// **What it does.** Draws three list sections and skips any it has nothing for.
/// The well at the top is the space a MoveKit animation will occupy — exercise
/// identity is that library's slug precisely so a purchased file drops in
/// without a mapping layer, so the placeholder is sized for what will land in
/// it rather than being a thin banner that would have to be redrawn. The facts
/// come from `ExerciseAbout`. Instructions are drawn only when the entry has
/// them, which is about one in five: an exercise with none shows none, not an
/// empty heading.
///
/// **How it is used.** `ExerciseDetailView` puts it above the record. An
/// exercise the catalog has no entry for draws nothing at all — an id the
/// catalog does not know is not a movement this app can describe, and guessing
/// from the name is how a record starts describing the wrong lift.
///
/// **What it depends on.** `Exercise` from LiftingKit, `ExerciseAbout` for the
/// words, `Spacing` and `Radius`. It reads no store and writes nothing.
struct ExerciseAboutSections: View {

    /// The catalog entry, or `nil` when there is none for this exercise.
    let entry: Exercise?

    /// How tall the demonstration well stands. A MoveKit loop is a wide frame
    /// of a person lifting; four-by-three holds one without letting it take the
    /// whole screen from the numbers underneath.
    private static let mediaAspectRatio: CGFloat = 4 / 3

    var body: some View {
        if let entry {
            Section {
                demonstration
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(ExerciseAbout.facts(for: entry)) { fact in
                    LabeledContent(fact.label, value: fact.value)
                        .font(.barbellSupport)
                }
            }

            if !entry.instructions.isEmpty {
                Section("How to perform it") {
                    ForEach(Array(entry.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.standard) {
                            Text("\(index + 1)")
                                .font(.barbellSupport)
                                .foregroundStyle(.secondary)
                            Text(step)
                                .font(.barbellBody)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1). \(step)")
                    }
                }
            }
        }
    }

    /// The demonstration's place, held open and honestly empty.
    ///
    /// It says what it is rather than pretending to be loading something: no
    /// animation ships yet, and a spinner over an empty box would be the screen
    /// claiming a file is on its way.
    private var demonstration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.large)
                .fill(.quaternary)
            VStack(spacing: Spacing.snug) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title)
                Text("Demonstration coming soon")
                    .font(.barbellSupport)
            }
            .foregroundStyle(.secondary)
        }
        .aspectRatio(Self.mediaAspectRatio, contentMode: .fit)
        .padding(.vertical, Spacing.snug)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demonstration coming soon")
    }
}
