import SwiftUI
import LiftingKit

/// The mark a session carries in a list, drawn.
///
/// **What it does.** Turns the name the plan chose — `strength`, `intervals` —
/// into the symbol this build draws for it. The mapping lives here and nowhere
/// else: which glyph a name resolves to is the app's business, and changing one
/// must not be a change to the format the coach writes.
///
/// **Why the app does not choose the mark.** A session's name is whatever the
/// coach called it, so inferring a glyph from `Push` or `Upper A` would be the
/// app deciding what a session trains from words it does not control. He picks
/// from a closed set instead — `SessionIcon.all` — and `PlanImporter` refuses a
/// name this build cannot draw rather than drawing nothing.
///
/// **What it depends on.** `SessionIcon` from LiftingKit, `Palette` and the type
/// ramp. It reads no model and holds no state.
struct SessionIconView: View {

    let icon: SessionIcon

    var body: some View {
        Image(systemName: Self.symbol(for: icon))
            .font(.supersetTitle)
            // **Ink, because the theme is a fill and never a line.** This file
            // already says so twice — `Palette.ink` is *every line and every
            // word this app draws in something other than grey*, and the chart
            // states it again for a plotted series. These marks are line art of
            // a person, and the highlighter rendered them as a bright smear on
            // cream that read worse than the grey it replaced. Green was tried
            // on Jon's call and looked wrong for exactly the reason the rule
            // exists.
            //
            // `muted` was the other end of the same mistake: the one mark
            // distinguishing a session from every other row drawn in the grey
            // reserved for words that qualify something. Full-strength ink is
            // what a mark that carries information gets.
            //
            // No disc behind it either. The glyph is the mark; a filled shape
            // around it would be a second one saying nothing the first does not.
            .foregroundStyle(Palette.ink)
            .accessibilityHidden(true)
    }

    /// The system symbol each name is drawn as.
    ///
    /// A name with no symbol here draws the barbell rather than nothing, which
    /// cannot happen through the front door — `PlanImporter` refuses an unknown
    /// name — and is the quiet answer if a stored day ever outlives its mark.
    nonisolated static func symbol(for icon: SessionIcon) -> String {
        switch icon {
        case .strength: "figure.strengthtraining.traditional"
        case .accessory: "dumbbell.fill"
        case .core: "figure.core.training"
        case .mobility: "figure.flexibility"
        case .run: "figure.run"
        case .row: "figure.rower"
        case .stairs: "figure.stair.stepper"
        case .intervals: "figure.highintensity.intervaltraining"
        case .walk: "figure.walk"
        case .conditioning: "figure.mixed.cardio"
        case .cycle: "figure.outdoor.cycle"
        case .elliptical: "figure.elliptical"
        case .swim: "figure.pool.swim"
        case .hike: "figure.hiking"
        case .climb: "figure.climbing"
        case .jumpRope: "figure.jumprope"
        case .combat: "figure.boxing"
        case .gymnastics: "figure.gymnastics"
        default: "figure.strengthtraining.traditional"
        }
    }
}
