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
    /// The colour the block is known by, or `nil` when its plan chose none.
    ///
    /// **The identity rides the element that was already there.** A block having
    /// a colour is worth seeing at a glance, and this rule is the one thing on
    /// the row that is already a band of colour — so the tint colours it rather
    /// than the app growing a dot, a rail or a coloured field for the same job.
    /// The track carries it faintly so a block nobody has trained yet still
    /// reads as itself rather than as an empty grey line.
    var tint: BlockTint? = nil

    var body: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * min(max(fraction, 0), 1)
            let colour = tint.map { Palette.blockTint($0) } ?? Palette.accent
            ZStack(alignment: .leading) {
                Capsule().fill(tint == nil ? Palette.rule : colour.opacity(0.22))
                Capsule().fill(colour).frame(width: filled)
            }
        }
        .frame(height: ProgressMetrics.height)
        .accessibilityHidden(true)
    }
}
