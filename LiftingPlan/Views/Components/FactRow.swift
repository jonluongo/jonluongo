import SwiftUI

/// One stated fact: what it is called on the left, what it says on the right.
///
/// **What it does.** Draws a label and its value as a row of a panel. A value
/// short enough to share the line sits against the right edge, so a column of
/// figures — `182 lb`, `60 min` — reads down the page. A value too long for the
/// line wraps underneath the label instead, aligned left with everything else on
/// the screen.
///
/// That second case is the reason this exists. Keeping the value right-aligned
/// while it wrapped left the tail of a sentence stranded against the right edge
/// — *"…without losing"* on one line and *"the squat"* alone on the next — which
/// reads as a mistake rather than as a paragraph. A short value and a sentence
/// are different shapes and the row draws each as what it is.
///
/// **How it is used.** Give it two strings. `ExerciseAboutSections` states what
/// the catalog holds about a movement and `AccountView` what Claude has been
/// told about the lifter; they are the same kind of statement and were two
/// designs, so they are one now.
///
/// **What it depends on.** `Spacing`, `Palette` and the type ramp. It reads no
/// model.
struct FactRow: View {

    let label: String
    let value: String

    var body: some View {
        // The one-line arrangement is offered first and taken when it fits.
        // `fixedSize` on the value is what makes the choice real: without it the
        // value would truncate rather than overflow, so the candidate would
        // always report that it fits and the wrapping one would never be
        // reached.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.standard) {
                labelText
                Spacer(minLength: Spacing.standard)
                valueText.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                labelText
                valueText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var labelText: some View {
        Text(label)
            .font(.supersetSupport)
            .foregroundStyle(Palette.muted)
    }

    private var valueText: some View {
        Text(value)
            .font(.supersetSupport)
            .foregroundStyle(Palette.ink)
    }
}
