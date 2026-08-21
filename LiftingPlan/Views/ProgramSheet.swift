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
    @Environment(DocumentTransportBox.self) private var transport: DocumentTransportBox?
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var failure: String?

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
                // **Edit, not a form.** The coach writes these; the user
                // corrects one when it is wrong about him, in the same markdown
                // the coach edits. See `NoteEditor`.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { editing = true }
                }
                CloseToolbarItem("Close program") { dismiss() }
            }
            .sheet(isPresented: $editing) {
                NoteEditor(note: .program, text: notes?.text(of: .program) ?? NoteFile.program.template) { edited in
                    save(edited)
                }
            }
            .alert("Couldn't save your edit", isPresented: .constant(failure != nil)) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    /// Writes the correction where the coach will read it, and mirrors it so the
    /// screen behind is not a pass behind.
    ///
    /// **A failed write is shown, not swallowed.** A correction he believes he
    /// made and the coach never sees is the worst outcome available here — the
    /// next block is written against the thing he thought he fixed.
    private func save(_ text: String) {
        do {
            try transport?.value.writeNote(text, as: .program)
            try notes?.mirror(text, as: .program)
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
