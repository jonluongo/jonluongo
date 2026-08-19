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
/// **How it is used.** Presented from the exercise's menu with whatever he
/// wrote last, and `onSave` is called with the text he leaves — trimmed, and
/// `nil` when he has cleared it, so a note emptied is a note gone rather than
/// an empty one kept.
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
                        .panelRow(.only)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
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
