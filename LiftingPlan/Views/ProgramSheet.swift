import SwiftUI

/// What this programme is for, in the coach's words.
///
/// **What it does.** Renders `program.md`: the approach, what is being
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
                MarkdownView(text: notes?.text(of: .program) ?? NotesStore.Note.program.template)
                    .padding(Spacing.section)
            }
            .background(Palette.surface)
            .navigationTitle("The programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
