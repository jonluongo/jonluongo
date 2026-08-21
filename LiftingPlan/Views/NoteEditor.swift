import SwiftUI
import LiftingKit

/// Where the user fixes something the coach got wrong.
///
/// **What it does.** Opens one of the two markdown files as text, and writes it
/// back to the shared folder when he is done.
///
/// **It is the file, not a form.** The app asks him nothing — that is the whole
/// premise — and a screen of labelled fields would be exactly the interview this
/// app exists not to conduct. What it offers instead is the same markdown the
/// coach edits, so there is one shape of edit, one thing to review, and nothing
/// for the app to reconcile between two vocabularies. He is correcting a
/// document, not answering questions.
///
/// **Nothing is parsed on the way in or out.** Whatever he types is what the
/// coach reads. The app has no opinion about the headings and will not repair
/// them, because the moment it starts understanding this text it starts being
/// able to be wrong about it.
///
/// **What it depends on.** `NoteFile` from LiftingKit for the name and the
/// template, and a caller to do the writing — it holds text and hands it back.
struct NoteEditor: View {

    let note: NoteFile
    /// What is on file now. The editor starts from this rather than the
    /// template, so opening it on an unwritten note gives him the headings to
    /// write under rather than a blank page.
    let text: String
    /// Called with the edited text, or not at all when nothing changed.
    var onSave: (String) -> Void

    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(note: NoteFile, text: String, onSave: @escaping (String) -> Void) {
        self.note = note
        self.text = text
        self.onSave = onSave
        _draft = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.supersetBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.ink)
                .scrollContentBackground(.hidden)
                .background(Palette.surface)
                .padding(.horizontal, PanelMetrics.inset)
                .navigationTitle(note.basename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // **Saving is the confirmation, so it is a word.** Every
                    // other sheet in the app closes with an `xmark` because
                    // closing is all it does; this one writes a file the coach
                    // reads next, and a glyph that could mean *discard* is the
                    // wrong thing to put on it.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            if draft != text { onSave(draft) }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                    // Cancel is the way out that changes nothing, named rather
                    // than drawn, so the pair reads as a choice.
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}
