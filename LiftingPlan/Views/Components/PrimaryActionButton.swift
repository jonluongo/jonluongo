import SwiftUI

/// The one full-width button this app draws.
///
/// **What it does.** "Start workout", "Finish workout" and "Start 2min" were
/// three copies of `.fontWeight(.semibold)` + `.frame(maxWidth: .infinity)` +
/// `.borderedProminent`, and the one on the most-used screen had a different
/// height and a different colour from the other two. This is that button, once,
/// at one height that clears the 44pt minimum.
///
/// **How it is used.** Give it a title, a symbol when it has one, and how much
/// of the screen it is entitled to — see `Prominence`. There is no tint to pass.
///
/// **Colour was tried twice and is gone.** Finishing was tinted green first, on
/// the grounds that green means done elsewhere in the app — which is exactly why
/// it did not belong: green marks a fact the record already holds, and this
/// button is the act that creates that fact, not the fact. The theme replaced it
/// and had the milder version of the same problem — the brightest thing on the
/// screen was the one thing the user had not done yet. It is ink now, on Jon's
/// call. **What the record holds is coloured; what you can do is simply legible.**
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
        /// The thing to do: a slab of ink with the word inverted out of it. A
        /// screen gets one.
        ///
        /// It was the highlighter, and Jon's call is that it is not: *"finish
        /// workout button should be black not yellow."* The theme still marks
        /// what the record holds — a ticked box, the wash under a session
        /// trained — and the act that creates the record is now the plainest
        /// thing on the screen rather than the brightest.
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
        /// The same as `quiet`, in the one colour that means this does not come
        /// back. A slab would give the most destructive control on its screen
        /// the most weight; the word alone gives it the least, and the
        /// confirmation that follows is where the deciding actually happens.
        case danger
        /// The beat after an act lands: the highlighter, with the word in ink on
        /// it. **This is the one place the accent belongs on a button** — it
        /// means *in the record*, and for the second after finishing that is
        /// exactly what the button is reporting. It is not an action; nothing
        /// happens if it is pressed during it.
        case recorded
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
        case .primary: Palette.ink
        case .recorded: Palette.accent
        case .tentative: Palette.rule
        case .quiet, .danger: .clear
        }
    }

    /// What the word is written in. `onInk` is ink inverted, for the one fill
    /// darker than the text that would otherwise sit on it; the rule is lighter
    /// than ink in either appearance, and a quiet button has no ground at all.
    private var foreground: Color {
        switch prominence {
        case .primary: Palette.onInk
        case .recorded: Palette.onAccent
        case .tentative, .quiet: Palette.ink
        case .danger: Palette.destructive
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
        PrimaryActionButton(title: "Start workout", systemImage: "play.fill") {}
        PrimaryActionButton(title: "Finish workout", systemImage: "checkmark") {}
        PrimaryActionButton(
            title: "Finish workout", systemImage: "checkmark", prominence: .tentative) {}
        PrimaryActionButton(
            title: "Mark as unfinished", systemImage: "arrow.uturn.backward",
            prominence: .quiet) {}
    }
    .padding()
}
