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
/// words and `Spacing`. It reads no store and writes nothing.
///
/// **There is no demonstration well.** A four-by-three placeholder stood at the
/// top of this screen reading "Demonstration coming soon" — the largest element
/// on the page, promising a feature that does not exist and telling a lifter
/// nothing about the movement he opened it to read. It comes back when there is
/// an animation to put in it.
struct ExerciseAboutSections: View {

    /// The catalog entry, or `nil` when there is none for this exercise.
    let entry: Exercise?

    var body: some View {
        if let entry {
            Section {
                let facts = ExerciseAbout.facts(for: entry)
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    FactRow(label: fact.label, value: fact.value)
                        .panelRow(.at(index, of: facts.count))
                        .listRowSeparator(.hidden)
                }
            }

            if !entry.instructions.isEmpty {
                Section {
                    SectionHeading("How to perform it")
                    ForEach(Array(entry.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.standard) {
                            Text("\(index + 1)")
                                .font(.supersetSupport)
                                .foregroundStyle(Palette.muted)
                            Text(step)
                                .font(.supersetBody)
                                .foregroundStyle(Palette.ink)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1). \(step)")
                        .panelRow(.at(index, of: entry.instructions.count))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }
}
