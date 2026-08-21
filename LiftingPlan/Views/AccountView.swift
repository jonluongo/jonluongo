import SwiftUI
import LiftingKit

/// Everything on record about the lifter, in his coach's words.
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
/// the coach owns this file, and the app asks the lifter nothing.
struct AccountView: View {

    @Environment(NotesStore.self) private var notes: NotesStore?
    @Environment(\.dismiss) private var dismiss

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
                CloseToolbarItem("Close account") { dismiss() }
            }
        }
    }
}
