import SwiftUI
import UIKit

/// The one thing the session still needs from a toolbar: a way out of a number
/// pad.
///
/// **What it does.** Puts `Done` above the keyboard. Nothing else — the close
/// button went when the session stopped being a sheet over a preview and became
/// the app's only screen, and the elapsed clock moved into the header beside
/// the session's name, which is the one place on the screen that is not part of
/// the log.
///
/// **How it is used.** `ActiveWorkoutView` passes it to `.toolbar`.
///
/// **What it depends on.** SwiftUI, and `UIApplication` for dismissing the
/// keyboard.
struct ActiveWorkoutToolbar: ToolbarContent {

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        // A number pad has no return key, so without this the only way out of a
        // weight field is to scroll the list — which is a poor thing to require
        // of someone holding the phone in one hand between sets.
        //
        // **This one stays a word, and is the only one that does.** Every
        // presented screen closes with `CloseToolbarItem`'s `xmark`; this
        // dismisses a keyboard rather than a screen, which is a different act
        // and one iOS has already taught with this exact word in this exact
        // place. An `xmark` above the keys would read as *discard what I typed*.
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { Self.dismissKeyboard() }
        }
    }

    /// Resigns whatever field is first responder. The entry fields live inside
    /// `SetRowView`, several levels down and one per set, so threading a
    /// `FocusState` binding to each of them would cost more than it is worth
    /// for a button that always means the same thing.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}
