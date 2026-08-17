import SwiftUI
import SwiftData
import LiftingKit

/// The quiet line under one set row: what the plan asked of *this* set beyond
/// the two numbers already in it, and the effort the lifter gives back.
///
/// **What it does.** Draws at most two things. On the left, the sentence
/// describing this set — "RPE 9", "Drop set", "last set AMRAP" — which used to
/// live in a numbered block above the table and was off the top of the screen
/// by the time the lifter reached set four. On the right, the one field that
/// writes `LoggedSet.rpe`, which the snapshot has always reported and no screen
/// could ever fill in.
///
/// **How it is used.** `SetRowView` puts one under itself and draws it at all
/// only when there is something to draw: `detail` is `nil` and `invitesEffort`
/// is `false` for an ordinary set of an ordinary prescription, so three sets of
/// eight gain nothing. `PrescriptionSummary.detail(for:in:)` decides the first,
/// and `EffortEntry.isInvited(by:)` the second — the field appears only where
/// the plan named an intensity target, because a permanent effort column would
/// cost every row on every screen forever to ask a question nobody asked.
///
/// **What it depends on.** `EffortEntry` for the reading and writing,
/// `SetTableMetrics` for the geometry so the field sits under the column above
/// it, and `LoggedSet`. It judges nothing: a rating is stored as typed, and an
/// empty field clears it to *no rating* rather than to a rating of zero — a set
/// nobody rated said nothing about how it felt, and one rated zero made a claim.
struct SetDetailLine: View {
    @Bindable var set: LoggedSet
    /// What this set asks that the exercise's header has not already said, or
    /// `nil` when it asks nothing of its own.
    let detail: String?
    /// The intensity the plan asked of this set, or `nil` when it asked none —
    /// which is the only reason to ask how hard it felt. It is the target
    /// itself rather than a flag, because the field is labelled with the scale
    /// the plan named and shows the number it asked for.
    let intensity: IntensityTarget?
    /// How this row is named aloud — "set 2", "warm-up set" — so the field
    /// says which set it rates. Every row on the screen is otherwise identical.
    let spokenSetName: String

    /// The rating as the text of the field it is typed into. Cleared to absent
    /// rather than to zero, exactly as the weight and distance fields are.
    private var effortText: Binding<String> {
        Binding(
            get: { EffortEntry.text(for: set.rpe) },
            set: { set.rpe = EffortEntry.rating(from: $0) }
        )
    }

    var body: some View {
        HStack(spacing: SetTableMetrics.columnGutter) {
            if let detail {
                Text(detail)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let intensity {
                Text(IntensityPrescription.scaleName(for: intensity))
                    .font(.barbellLabel)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                // Supporting type rather than Metric: this qualifies the row
                // above it. The field is still held to the tap minimum, since
                // it is tapped with chalk on the hands like everything else here.
                TextField(IntensityPrescription.target(for: intensity), text: effortText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.barbellSupport)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(
                        width: SetTableMetrics.entryColumnWidth,
                        height: SetTableMetrics.entryHeight
                    )
                    .background(
                        Color(.tertiarySystemFill), in: .rect(cornerRadius: Radius.small)
                    )
                    .accessibilityLabel(
                        "\(IntensityPrescription.scaleName(for: intensity)) for \(spokenSetName)"
                    )
                    .accessibilityHint(
                        "The block asked for \(IntensityPrescription.target(for: intensity))"
                    )
                // The completion column, left empty, so the field sits under
                // the one above it rather than under the check.
                Spacer().frame(width: SetTableMetrics.checkColumnWidth)
            }
        }
    }
}
