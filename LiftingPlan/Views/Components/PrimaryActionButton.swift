import SwiftUI

/// The one full-width button this app draws.
///
/// **What it does.** "Start Workout", "Finish Workout" and "Start 2min" were
/// three copies of `.fontWeight(.semibold)` + `.frame(maxWidth: .infinity)` +
/// `.borderedProminent`, and the one on the most-used screen had a different
/// height and a different colour from the other two. This is that button, once,
/// at one height that clears the 44pt minimum.
///
/// **How it is used.** Give it a title, a symbol when it has one, and how much
/// of the screen it is entitled to — see `Prominence`. There is no tint to pass.
///
/// **Green was tried and was wrong.** Finishing a workout was tinted green on
/// the grounds that green means done elsewhere in the app — and that is exactly
/// why it does not belong here. Green marks a fact the record already holds: a
/// set that was ticked, a session that was logged. This button is not that fact,
/// it is the act that creates it, and colouring it as though it had already
/// happened pre-empts the lifter's own decision. It also put a second saturated
/// colour into a palette that is otherwise one accent and neutrals, and a
/// full-width slab of system green beside the app's orange looked like two apps.
/// The rule that replaced it is shorter: **the accent is what you can do, green
/// is what the record says.**
///
/// **What it depends on.** `Spacing`, `TapTarget`, and SwiftUI's button styles.
/// It performs no action of its own and knows nothing about what it starts or
/// finishes.
struct PrimaryActionButton: View {

    /// How much of the screen this action is entitled to.
    ///
    /// **None of them is ever disabled.** Whether he is finished is his to say
    /// and not the app's, and a correction has to stay available or the record
    /// cannot be corrected. What changes is how loudly the button asks to be
    /// pressed.
    enum Prominence {
        /// The thing to do: the highlighter at full strength, with ink on it.
        /// A screen gets one.
        case primary
        /// Available, but not what the screen is for yet — finishing a session
        /// with sets still unticked. The same shape, filled with the rule's own
        /// weight and written in ink.
        ///
        /// It was `muted` — a mid-grey slab with white on it — which reads as
        /// *disabled* rather than as *not yet*, and this button is never
        /// disabled. A fill light enough to write ink on is a button that is
        /// plainly there and plainly not the lit one.
        case tentative
        /// A correction rather than an action: taking a finished session back.
        /// No fill at all, just the word. It is the least a button can be while
        /// still being one, which is what a thing you press by mistake should
        /// be.
        case quiet
    }

    let title: String
    /// The symbol beside the title, or `nil` for a title on its own.
    var systemImage: String?
    var prominence: Prominence = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .fontWeight(.semibold)
                // Stated rather than inherited. A prominent button draws its
                // title against the tint but leaves the symbol beside it to the
                // accent, so a button whose fill was not the accent came out
                // with a title and a symbol in two different colours.
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.tight)
        }
        .buttonStyle(.borderedProminent)
        // A quiet button is the same button with nothing behind it. Drawn as a
        // bare `Button` instead it would lose the height and the full width,
        // and the foot of the screen would move depending on which state it was
        // in — which is the fault this control was made one thing to fix.
        .tint(fill)
        // The floor, not the height: the style's own padding already clears
        // 44pt at ordinary text sizes, and this catches the case where it
        // would not.
        .frame(minHeight: TapTarget.minimum)
    }

    /// The fill behind the word. `clear` is not an absence of a decision here —
    /// it is the decision.
    private var fill: Color {
        switch prominence {
        case .primary: Palette.accent
        case .tentative: Palette.rule
        case .quiet: .clear
        }
    }

    /// What the word is written in. Ink for all three: the highlighter and the
    /// rule are both lighter than the text that sits on them, in either
    /// appearance, and `onAccent` is ink that does not follow the appearance
    /// because its ground does not either.
    private var foreground: Color {
        switch prominence {
        case .primary: Palette.onAccent
        case .tentative, .quiet: Palette.ink
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

#Preview("Primary action") {
    VStack(spacing: Spacing.section) {
        PrimaryActionButton(title: "Start Workout", systemImage: "play.fill") {}
        PrimaryActionButton(title: "Finish Workout", systemImage: "checkmark") {}
        PrimaryActionButton(
            title: "Finish Workout", systemImage: "checkmark", prominence: .tentative) {}
        PrimaryActionButton(
            title: "Mark as Unfinished", systemImage: "arrow.uturn.backward",
            prominence: .quiet) {}
    }
    .padding()
}
