import SwiftUI
import LiftingKit

/// Everything on record about the user, in his coach's words.
///
/// **What it does.** Renders `ACCOUNT.md`. That is the whole of it.
///
/// **It used to be a form's worth of rows.** Goal, experience, constraints,
/// equipment, both avoid lists, bodyweight and every strength baseline, each a
/// labelled field with a value or a dash. Nine fields, none of which anything
/// computed with — they were display-only, which is what made them prose. A
/// paragraph the coach wrote says more than nine fields he had to fit into.
///
/// **Nothing is read out of it.** The screen draws the text; no value is
/// extracted, because the moment one has to be, it belongs in a table.
///
/// **What it depends on.** `NotesStore` and `MarkdownView`. It writes nothing:
/// the coach owns this file, and the app asks the user nothing.
struct AccountView: View {

    @Environment(NotesStore.self) private var notes: NotesStore?
    @Environment(DocumentTransportBox.self) private var transport: DocumentTransportBox?
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownView(text: notes?.text(of: .account) ?? NoteFile.account.template)
                    .padding(Spacing.section)
            }
            .background(Palette.surface)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **Edit, not a form.** The coach writes these; the user
                // corrects one when it is wrong about him, in the same markdown
                // the coach edits. See `NoteEditor`.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { editing = true }
                }
                CloseToolbarItem("Close account") { dismiss() }
            }
            .sheet(isPresented: $editing) {
                NoteEditor(note: .account, text: notes?.text(of: .account) ?? NoteFile.account.template) { edited in
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
            try transport?.value.writeNote(text, as: .account)
            try notes?.mirror(text, as: .account)
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
