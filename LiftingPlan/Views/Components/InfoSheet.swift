import SwiftUI

/// The shape every "what is this" screen in the app takes.
///
/// **What it does.** Draws the chrome an information sheet shares — the surface,
/// the plain list, the inline title, and the `xmark` that closes it — so the two
/// of them cannot drift apart. A block's information and an exercise's are the
/// same kind of screen: a name at the top and panels of stated facts under it,
/// read and not edited.
///
/// **How it is used.** `InfoSheet("Barbell Bench Press") { sections }`, presented
/// as a sheet. Its content is `Section`s of rows drawn with `panelRow`, headed by
/// `SectionHeading` — the components every other list in the app uses, which is
/// what makes the two sheets siblings rather than two designs that happen to
/// agree today.
///
/// **Both are reached by the same mark.** `info`, on the block's toolbar
/// and in an exercise's menu. One glyph, one job: *tell me about this*.
///
/// **What it depends on.** `Palette`. It holds no state and reads no model.
struct InfoSheet<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        List {
            content()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // **The grabber was the only way out, and a grabber is a gesture.**
        // Every other presented screen states its exit in the corner; this one
        // left the user to discover a drag. It is the same `xmark`, doing the
        // same one job.
        .toolbar {
            CloseToolbarItem("Close \(title)") { dismiss() }
        }
    }
}
