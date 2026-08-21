import SwiftUI

/// The way out of a presented screen, in the corner everyone already reads as
/// the way out.
///
/// **What it does.** Puts an `xmark` in the top-right of a sheet's toolbar and
/// runs the action that closes it. Nothing else — it does not save, confirm or
/// decide, and a screen whose corner button does any of those must not use this.
///
/// **How it is used.** `CloseToolbarItem { dismiss() }` inside a `.toolbar`,
/// with a label naming what is being closed for anyone who cannot see the glyph.
///
/// **Why one component rather than the word "Done".** Five presented screens had
/// four different answers: the session drew an `xmark`, the user's page, the
/// programme and the note sheet each drew their own *Done*, and the exercise
/// page drew nothing at all and left the grabber to do it. *Done* is a claim
/// about the work — it reads as *I have finished writing this* — which on a
/// screen that only displays is a question the user never asked, and on a
/// screen that does save is a second control competing with the real one. An
/// `xmark` says close and says nothing else, which is true of every one of them.
///
/// **What it depends on.** SwiftUI only. It holds no state and reads no model.
struct CloseToolbarItem: ToolbarContent {

    /// What is being closed, for VoiceOver: *Close workout*, *Close note*. The
    /// glyph is identical everywhere, so the sentence is the only thing that
    /// says which screen is going away.
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(label)
        }
    }
}
