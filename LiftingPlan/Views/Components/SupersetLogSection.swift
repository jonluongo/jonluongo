import SwiftUI
import SwiftData
import LiftingKit

/// The editable body of one group's card: the group's rest, and its sets laid
/// out round by round.
///
/// **What it does.** Draws the rounds rather than the exercises. Round one is A1
/// then A2, round two is A1 then A2 again — which is how the work is actually
/// performed, and what a lifter mid-superset needs in front of him. The whole of
/// A1 followed by the whole of A2 would be the same rows in the order nobody
/// trains them in.
///
/// **The one behavioural difference is the rest.** It runs when the *round*
/// finishes, not when a set does — resting only after the group is the whole
/// definition of a superset, and it is the reason the grouping is worth
/// expressing at all. Ticking A1 starts nothing; ticking the last row of the
/// round starts the group's rest; taking any of them back stops it.
///
/// **How it is used.** `ActiveWorkoutView` draws one per grouped entry, beneath
/// `SupersetHeaderView`. Warm-ups sit above round one, because a warm-up belongs
/// to a movement rather than to a round.
///
/// **What it depends on.** `ExerciseGroup` from Services, `SetRowView` and
/// `SetRowView` — the same row an ungrouped exercise
/// draws — `SetRowPrescription` for what each row is shown, and
/// `RestPrescription` for the rest line. The only thing it writes is the log.
struct SupersetLogSection: View {

    let group: ExerciseGroup
    let profile: UserProfile
    let plans: [TrainingPlan]
    /// Adds one round: one working row to every movement of the group, because
    /// the round is the unit of work.
    var onAddRound: (ExerciseGroup) -> Void
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    /// Told the group and whether the round the lifter just touched is now
    /// complete. The screen decides what to run; this decides when.
    var onRoundChanged: (ExerciseGroup, Bool) -> Void
    var body: some View {
        Group {
            ForEach(Array(rows.warmups.enumerated()), id: \.element.id) { index, row in
                setRow(row, position: .middle)
            }

            ForEach(Array(rows.rounds.enumerated()), id: \.element.id) { index, round in
                Text("ROUND \(round.number)")
                    .font(.barbellLabel)
                    .tracking(Font.labelTracking)
                    .foregroundStyle(Palette.muted)
                    .accessibilityAddTraits(.isHeader)
                    // The top of the panel when the group prescribes no warm-up,
                    // which is the ordinary case. It was always `.middle`,
                    // because the column header used to be the first row — and
                    // deleting that header left the panel with no rounded top
                    // and nothing to say where it began.
                    .panelRow(.middle)
                    .listRowSeparator(.hidden)
                ForEach(round.rows) { row in
                    setRow(row)
                }
            }

            Button {
                onAddRound(group)
            } label: {
                Label("Add Round", systemImage: "plus")
                    .font(.barbellSupport)
                    .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .panelRow(.last)
            .listRowSeparator(.hidden)
        }
    }

    /// The group's rows, gathered once per redraw rather than per row.
    private var rows: GroupRounds {
        GroupRounds(group: group, plans: plans, unit: profile.displayUnit)
    }

    private func setRow(
        _ row: GroupRounds.Row, position: PanelPosition = .middle
    ) -> some View {
        setRowBody(row)
            .panelRow(position, insets: SetTableMetrics.rowInsets)
            .listRowSeparator(.hidden)
    }

    private func setRowBody(_ row: GroupRounds.Row) -> some View {
        SetRowView(
            set: row.set,
            identity: row.identity,
            repTargetText: RepPrescription.targetText(for: row.prescribed?.repRange),
            loadTargetText: row.loadTarget,
            prescriptionDetail: PrescriptionSummary.detail(
                for: row.prescribed, in: row.member),
            measure: row.measure,
            unit: profile.displayUnit,
            onCompletionChanged: { completed in
                // Rest belongs to the round, so what matters is whether the
                // round is now finished — not whether this set is. A set taken
                // back can only end a round's completeness, never begin it.
                onRoundChanged(group, completed && rows.isComplete(round: row.round))
            }
        )
        .listRowBackground(row.set.isCompleted ? Color.green.opacity(0.12) : nil)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDeleteSet(row.set, row.member) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
