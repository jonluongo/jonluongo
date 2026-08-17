import SwiftUI

/// The one full-width button this app draws.
///
/// **What it does.** "Start Workout", "Finish Workout" and "Start 2min" were
/// three copies of `.fontWeight(.semibold)` + `.frame(maxWidth: .infinity)` +
/// `.borderedProminent`, and the one on the most-used screen had a different
/// height and a different colour from the other two. This is that button, once,
/// at one height that clears the 44pt minimum.
///
/// **How it is used.** Give it a title and, when it has one, a symbol. There is
/// no tint to pass: this button is the accent, always.
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
/// **What it depends on.** `Spacing`, `TapTarget`, and SwiftUI's prominent
/// button style. It performs no action of its own and knows nothing about what
/// it starts or finishes.
struct PrimaryActionButton: View {

    let title: String
    /// The symbol beside the title, or `nil` for a title on its own.
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .fontWeight(.semibold)
                // Stated rather than inherited. A prominent button draws its
                // title white against the tint but leaves the symbol beside it
                // to the accent, so a button whose fill was not the accent came
                // out with a title and a symbol in two different colours.
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.tight)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        // The floor, not the height: the style's own padding already clears
        // 44pt at ordinary text sizes, and this catches the case where it
        // would not.
        .frame(minHeight: TapTarget.minimum)
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
    }
    .padding()
}
