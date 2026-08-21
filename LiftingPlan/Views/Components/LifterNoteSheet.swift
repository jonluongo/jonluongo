import SwiftUI

/// Where the lifter writes what happened, in his own words.
///
/// **What it does.** Takes one free-text note about performing one movement
/// today — *knee hurt at the end*, *bar felt light* — and hands it back. It is
/// the only place in the app the lifter types prose, and the only thing he
/// tells the record that is not a number.
///
/// **It is not the coach's note.** That one is part of the prescription and
/// arrives with the plan; this is part of what happened and survives the next
/// plan. They are drawn the same way at the foot of the panel and stored apart,
/// because whichever of them wrote last would otherwise erase the other.
///
/// **How it is used.** Presented from the note line at the foot of the
/// exercise's panel with whatever he wrote last. `onSave` is called with the
/// text he leaves — trimmed, and `nil` when he has cleared it, so a note emptied
/// is a note gone rather than an empty one kept.
///
/// **It saves on the way out rather than behind a button**, so the corner can
/// hold the same `xmark` every other presented screen holds. See `onDisappear`.
///
/// **What it depends on.** `Palette`, `Spacing` and the type ramp. It reads no
/// model and writes nothing itself.
struct LifterNoteSheet: View {

    let exerciseName: String
    var onSave: (String?) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isWriting: Bool

    init(exerciseName: String, note: String?, onSave: @escaping (String?) -> Void) {
        self.exerciseName = exerciseName
        self.onSave = onSave
        _text = State(initialValue: note ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("How did it go?", text: $text, axis: .vertical)
                        .font(.supersetBody)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.ink)
                        .lineLimit(3...8)
                        .focused($isWriting)
                        .panelRow()
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem("Close note") { dismiss() }
            }
            // **The note is written on the way out, however he leaves.**
            // *Done* used to be the only thing that saved it, and the grabber
            // above it dismissed without saving — so the gesture iOS teaches for
            // closing a sheet silently threw away what he had typed. Committing
            // here catches the button, the grabber and the swipe with one path,
            // and it is what every other field in the app already does: a set
            // row writes when it loses focus, and nothing in this app has a
            // Save button.
            .onDisappear {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(trimmed.isEmpty ? nil : trimmed)
            }
            // Straight into the field: he opened this to write, and a keyboard
            // he has to summon is a tap between him and the thing he came for.
            .task { isWriting = true }
        }
        // Tall enough for the keyboard and the lines above it, and no taller:
        // this is one sentence, not a document.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
