import SwiftUI
import LiftingKit

/// What this programme is for, in the coach's words.
///
/// **What it does.** Renders `PROGRAM.md`: the approach, what is being
/// progressed, what to watch, and what makes a given block a deload.
///
/// **It replaced a panel of figures.** The routine's information sheet stated a
/// title, a goal, a length in weeks, a session length and a note — five fields
/// describing a shape the store no longer has. The character of a block is prose
/// now, which is why a block is a number and nothing else.
///
/// **What it depends on.** `NotesStore` and `MarkdownView`.
struct ProgramSheet: View {

    @Environment(NotesStore.self) private var notes: NotesStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownView(text: notes?.text(of: .program) ?? NoteFile.program.template)
                    .padding(Spacing.section)
            }
            .background(Palette.surface)
            .navigationTitle("Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem("Close program") { dismiss() }
            }
        }
    }
}
