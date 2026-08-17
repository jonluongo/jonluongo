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
/// nothing for a set that says nothing. `SessionDetailView` shows it, and only
/// when the sets differ from one another — a uniform prescription is already
/// stated in full above.
///
/// **It is the preview's, not the logging screen's.** A session being read
/// before it is trained has no rows to hang anything on, so the numbered block
/// is the only place its ramp can be seen whole. The logging screen dropped it:
/// there, every set already has a row, and a sentence about set four belongs
/// under set four rather than in a block the lifter has scrolled past by the
/// time he gets there. `PrescriptionSummary.detail(for:in:)` and `SetDetailLine`
/// are what replaced it.
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
