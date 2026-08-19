import SwiftUI

/// What the coach wrote alongside the block, printed as prose.
///
/// **What it does.** Gives `TrainingPlan.notes` a place on screen. The note is
/// the one thing in this app nobody else could have written — Strong and Hevy
/// have no author behind a plan — and it was accepted by the document, dropped
/// before the store, and then stored but rendered nowhere. It is set in body
/// type at full contrast for that reason: a grey caption is how an app says
/// "small print", and this is the opposite of small print.
///
/// **How it is used.** Hand it the note. Callers check for absence themselves —
/// a view that renders nothing still takes a row's padding in a `List`, so the
/// decision not to draw belongs where the section is built. The label above the
/// note says who is talking, because a block-level note and a note about one
/// exercise read identically without it.
///
/// **What it depends on.** `Spacing` and the type ramp. It reads no model and
/// holds no state.
struct CoachNoteView: View {

    /// The coach's words, exactly as stored. Never trimmed, never truncated:
    /// this view shows all of it, and a long note scrolls with the screen.
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            Text(note)
                .font(.supersetBody)
        }
        .padding(.vertical, Spacing.tight)
    }
}

#Preview("Coach note") {
    List {
        CoachNoteView(
            note: """
                Three heavy weeks then a deload. If the left shoulder complains \
                on the bench, stop the set and tell me.
                """
        )
    }
}
