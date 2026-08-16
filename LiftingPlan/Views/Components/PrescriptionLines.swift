import SwiftUI
import LiftingKit

/// The sets a plan asked for, numbered, one line each.
///
/// **What it does.** Draws a ramp or a drop set the way it was written — "1
/// 205 lb × 5", "2 225 lb × 5" — with the numbers in a gutter so they line up
/// and stay lined up past nine. It was written twice: the logging screen built
/// a real gutter, and the session preview interpolated `"\(index + 1)  \(line)"`
/// with two literal spaces, which indents differently once a set reaches 10 and
/// rendered the identical block at a different size one screen away.
///
/// **How it is used.** Hand it the exercise's `prescribedSets` and the unit to
/// read loads in; it asks `PrescriptionSummary` what each set says and draws
/// nothing for a set that says nothing. Callers decide *whether* to show it —
/// both do so only when the sets differ from one another, since a uniform
/// prescription is already stated in full above.
///
/// **What it depends on.** `PrescriptionSummary` for the words, `SetPrescription`
/// and `MassUnit` from LiftingKit, and `Spacing` and the type ramp for the
/// shape. It states nothing about the sets itself.
struct PrescriptionLines: View {

    let sets: [SetPrescription]
    let unit: MassUnit

    /// The index gutter, wide enough for two digits and scaled with the text
    /// in it, so a tenth set does not clip the way a fixed 14pt frame did.
    @ScaledMetric(relativeTo: .subheadline) private var gutter: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                let line = PrescriptionSummary.text(for: set, unit: unit)
                if !line.isEmpty {
                    HStack(spacing: Spacing.snug) {
                        Text("\(index + 1)")
                            .frame(width: gutter, alignment: .trailing)
                        Text(line)
                    }
                }
            }
        }
        .font(.barbellSupport)
        .foregroundStyle(.secondary)
    }
}
