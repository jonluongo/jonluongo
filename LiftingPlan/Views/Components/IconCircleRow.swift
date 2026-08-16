import SwiftUI

/// A glyph in a tinted circle, a title, a line under it, and an optional
/// control on the right.
///
/// **What it does.** Draws the app's one list-row shape. It was two shapes: the
/// exercise header on the logging screen and the day row on the plan screen
/// were the same construction written twice, and had already drifted six ways —
/// a 36pt circle against a 44pt one, 0.15 fill against 0.12, `.footnote`
/// against unset, accent title against primary, 1pt title gap against 2pt, and
/// `.caption` subtitle against `.subheadline`. Nobody chose any of that; it is
/// what happens to a pattern with no single home.
///
/// **How it is used.** Give it a symbol, the tint that symbol carries, and the
/// two lines of text. Pass a control as `trailing` when the row has one — it is
/// given a 44pt target whatever glyph it draws, which is how the overflow menu
/// stopped being 32pt. The title is `.primary`: it is content, and the tint
/// belongs on the circle, where a non-text element only owes 3:1 contrast.
///
/// **What it depends on.** `Spacing`, `TapTarget`, and the type ramp. It reads
/// no model — callers hand it strings, so the same row can describe a
/// prescribed exercise, a training day, or anything later that is also this
/// shape.
struct IconCircleRow<Trailing: View>: View {

    let systemImage: String
    /// The colour of the glyph and, at 12%, of the circle behind it. One
    /// opacity for every state: the day row used to change brightness as well
    /// as hue when a session was completed, which read as two changes.
    let tint: Color
    let title: String
    /// The line under the title, or `nil` when there is nothing to say. Never
    /// an empty string standing in for one.
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    /// The circle grows with the lifter's text size, so a glyph never rattles
    /// around inside a fixed disc at AX sizes.
    @ScaledMetric(relativeTo: .headline) private var diameter: CGFloat = 36

    private static var fillOpacity: Double { 0.12 }

    var body: some View {
        HStack(spacing: Spacing.standard) {
            ZStack {
                Circle()
                    .fill(tint.opacity(Self.fillOpacity))
                    .frame(width: diameter, height: diameter)
                Image(systemName: systemImage)
                    .font(.barbellBody)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .font(.barbellTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // A row with no control claims no room for one: an empty trailing
            // view given a 44pt frame would indent every row that has nothing
            // on its right.
            if Trailing.self != EmptyView.self {
                trailing()
                    .frame(minWidth: TapTarget.minimum, minHeight: TapTarget.minimum)
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}

extension IconCircleRow where Trailing == EmptyView {

    /// The row without a control on the right, which is most of them.
    init(systemImage: String, tint: Color, title: String, subtitle: String?) {
        self.init(systemImage: systemImage, tint: tint, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

#Preview("Icon circle row") {
    List {
        IconCircleRow(
            systemImage: "dumbbell.fill", tint: .accentColor,
            title: "Barbell Back Squat", subtitle: "4 sets · tempo 3-0-1-0"
        ) {
            Image(systemName: "ellipsis")
                .font(.barbellBody)
                .foregroundStyle(.secondary)
        }
        IconCircleRow(
            systemImage: "checkmark", tint: .green,
            title: "Monday", subtitle: "Lower · 3 exercises"
        )
    }
}
