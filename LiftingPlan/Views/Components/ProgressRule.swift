import SwiftUI
import LiftingKit

/// How much of a block is in the record, drawn as a rule.
///
/// **What it does.** Fills a hairline-tall track from the left in proportion to
/// what has been logged. It states the fraction the row already says in words —
/// `4 of 16 logged` — and adds nothing to it: no target, no pace, no verdict on
/// whether that is enough, because how much of a block should be done by now is
/// a training judgement and not the app's.
///
/// **Why a rule rather than a ring or a figure.** A row is wide and short, so a
/// full-width rule reads at a glance from the edge of the panel and costs one
/// line of height; a ring would claim the trailing slot the chevron holds, and a
/// percentage is a second number saying what the first already said.
///
/// **What it depends on.** `Palette`, `Radius` and `SetTableMetrics`. It holds
/// no state, and it is hidden from VoiceOver because the line above it is the
/// same fact in words.
struct ProgressRule: View {

    /// How much is logged, from 0 to 1. Values outside that are clamped, since a
    /// bar wider than its track is a drawing bug rather than a fact.
    let fraction: Double
    /// Whether the rule is drawn on a block's own coloured field, where ink and
    /// the accent both disappear and white is the only thing that reads.
    var onField: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(onField ? Color.white.opacity(0.28) : Palette.rule)
                Capsule().fill(onField ? Color.white : Palette.accent).frame(width: filled)
            }
        }
        .frame(height: ProgressMetrics.height)
        .accessibilityHidden(true)
    }
}
