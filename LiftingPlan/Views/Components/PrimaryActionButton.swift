import SwiftUI

/// The one full-width button this app draws.
///
/// **What it does.** "Start Workout", "Finish Workout" and "Start 2min" were
/// three copies of `.fontWeight(.semibold)` + `.frame(maxWidth: .infinity)` +
/// `.borderedProminent`, and the one on the most-used screen had a different
/// height and a different colour from the other two. This is that button, once,
/// at one height that clears the 44pt minimum.
///
/// **How it is used.** Give it a title and, when it has one, a symbol. `tint`
/// exists for a single named exception — finishing a workout is green, because
/// green means done everywhere else in the app — and is the accent otherwise.
/// It is not a theming hook: a third tint would mean the colour has stopped
/// meaning anything.
///
/// **What it depends on.** `Spacing`, `TapTarget`, and SwiftUI's prominent
/// button style. It performs no action of its own and knows nothing about what
/// it starts or finishes.
struct PrimaryActionButton: View {

    let title: String
    /// The symbol beside the title, or `nil` for a title on its own.
    var systemImage: String?
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .fontWeight(.semibold)
                // Stated rather than inherited. A prominent button draws its
                // title white against the tint but leaves the symbol beside it
                // to the accent, so the check on the green Finish button came
                // out orange — one button in two colours. Both tints here are
                // dark enough to carry white, which is the whole reason there
                // are only two.
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.tight)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
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
        PrimaryActionButton(title: "Finish Workout", tint: .green) {}
    }
    .padding()
}
