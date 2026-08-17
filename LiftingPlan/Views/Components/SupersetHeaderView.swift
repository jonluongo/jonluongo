import SwiftUI
import LiftingKit

/// The header of one group's card on the logging screen: what the group is, how
/// many rounds it runs, and which movement is A1 and which is A2.
///
/// **What it does.** Names the group in the words a lifter already reads —
/// *Superset A*, *Tri-set B* — and then legends it, because the rows below carry
/// only `A1` and `A2` and something has to say what those are. Each legend line
/// is the movement's name, what the plan asks of it and what Claude wrote about
/// it, with the menu of things there are to do to that movement rather than to
/// the group.
///
/// **How it is used.** `ActiveWorkoutView` puts one above each group's section,
/// where `ExerciseHeaderView` sits above an ungrouped exercise's. The two are
/// deliberately the same shape — `IconCircleRow` — so a card that happens to be
/// a superset does not read as a different kind of thing.
///
/// **What it depends on.** `ExerciseGroup` from Services, `IconCircleRow` for
/// the shape and `PrescriptionSummary` for the words. It writes nothing.
struct SupersetHeaderView: View {

    let group: ExerciseGroup
    var onShowInfo: (PlannedExercise) -> Void
    var onAddWarmup: (PlannedExercise) -> Void

    /// "3 rounds", or "3 rounds · tempo 3-0-1-0" where every movement shares a
    /// tempo. Nothing is summarised away: where they differ, each legend line
    /// says its own.
    private var subtitle: String {
        let rounds = group.prescribedRounds
        return "\(rounds) round\(rounds == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            IconCircleRow(
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                tint: .accentColor,
                title: group.title,
                subtitle: subtitle
            )
            ForEach(group.members) { member in
                legend(for: member)
            }
        }
    }

    /// One line of the legend: which movement `A1` is, and what it asks for.
    private func legend(for member: PlannedExercise) -> some View {
        HStack(spacing: Spacing.standard) {
            Text(group.notation(for: member) ?? "")
                .font(.barbellLabel)
                .monospaced()
                .foregroundStyle(.secondary)
                .frame(width: SetTableMetrics.setColumnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(member.displayName)
                    .font(.barbellBody)
                Text(prescription(of: member))
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
                // What Claude said about this movement, beside the movement he
                // said it about. An ungrouped exercise's note is stated on its
                // card by `ExerciseLogSection`; inside a group the card belongs
                // to the round rather than to one movement, so the legend line
                // naming the movement is the only place its note can attach to.
                if let note = note(of: member) {
                    Text(note)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { onShowInfo(member) } label: {
                    Label("About This Exercise", systemImage: "info.circle")
                }
                Button { onAddWarmup(member) } label: {
                    Label("Add Warmup Set", systemImage: "flame")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.barbellBody)
                    .foregroundStyle(.secondary)
                    .frame(width: TapTarget.minimum, height: TapTarget.minimum)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(member.displayName) options")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                "\(group.notation(for: member) ?? ""), \(member.displayName), "
                    + prescription(of: member),
                note(of: member),
            ].compactMap { $0 }.joined(separator: ". "))
    }

    private func prescription(of member: PlannedExercise) -> String {
        let summary = PrescriptionSummary.text(for: member)
        guard let tempo = member.tempo, !tempo.isEmpty else { return summary }
        return "\(summary) · tempo \(tempo)"
    }

    /// What Claude wrote about this movement, or `nil` when he wrote nothing.
    /// An empty note is nothing to draw, exactly as an absent one is.
    private func note(of member: PlannedExercise) -> String? {
        member.notes.flatMap { $0.isEmpty ? nil : $0 }
    }
}
