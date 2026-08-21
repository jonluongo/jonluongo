import SwiftUI
import LiftingKit

/// One of the coach's two notes, read and — when something is wrong — corrected.
///
/// **What it does.** Renders `ACCOUNT.md` or `PROGRAM.md`, and turns the same
/// screen into a text editor when the user taps *Edit*.
///
/// **One screen, two states — not two screens.** Editing opened a second sheet
/// over the first, so correcting a line meant a card sliding over the card that
/// showed it, and the thing being edited disappeared behind the thing editing
/// it. It is the same surface now: the prose becomes the text it was rendered
/// from, in place.
///
/// **It is the file, not a form.** The app asks him nothing — that is the
/// premise — and a screen of labelled fields would be exactly the interview this
/// app exists not to conduct. He edits the markdown the coach edits, so there is
/// one shape of edit and no second vocabulary to reconcile. Nothing is parsed on
/// the way in or out: the moment the app starts understanding this text it
/// starts being able to be wrong about it.
///
/// **What it depends on.** `NoteFile` and `DocumentTransport` from LiftingKit,
/// `NotesStore` for the local copy, and `MarkdownView` for the drawn form. It is
/// the only screen in the app that writes a file the coach reads.
struct NoteSheet: View {

    let note: NoteFile

    @Environment(NotesStore.self) private var notes: NotesStore?
    @Environment(DocumentTransportBox.self) private var transport: DocumentTransportBox?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String?
    @State private var failure: String?

    private var text: String { notes?.text(of: note) ?? note.template }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    TextEditor(text: Binding(get: { draft }, set: { self.draft = $0 }))
                        .font(.supersetBody)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Spacing.standard)
                } else {
                    ScrollView {
                        MarkdownView(text: text).padding(Spacing.section)
                    }
                }
            }
            .background(Palette.surface)
            .navigationTitle(note.rawValue.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Couldn't save your edit", isPresented: .constant(failure != nil)) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    /// **The corner that closes becomes the corner that saves.** Editing is a
    /// state of this screen, so the controls are its controls: *Save* is a word
    /// because it writes a file the coach reads next, and an `xmark` that could
    /// mean *discard* is the wrong mark to put on that.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let draft {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { self.draft = nil }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save(draft) }.fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit") { draft = text }
            }
            CloseToolbarItem("Close \(note.rawValue)") { dismiss() }
        }
    }

    /// Writes the correction where the coach will read it, and mirrors it so the
    /// rendered form behind is not a pass behind.
    ///
    /// **A failed write is shown, not swallowed**, and the draft is kept when it
    /// fails — dropping back to the prose would lose what he typed and leave him
    /// looking at the text he was correcting.
    private func save(_ edited: String) {
        guard edited != text else { return draft = nil }
        do {
            try transport?.value.writeNote(edited, as: note)
            try notes?.mirror(edited, as: note)
            draft = nil
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
