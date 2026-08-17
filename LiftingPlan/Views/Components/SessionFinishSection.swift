import SwiftUI

/// The end of a session being logged: the one control that changes what the
/// record says about it.
///
/// **What it does.** Draws the last section of the logging screen — `Finish` on
/// a session still open, and on a finished one the fact that it is finished
/// beside the way to take that back. It holds no state and reads no model:
/// it is told which of the two it is, and reports which was pressed.
///
/// **Why it is here rather than in the toolbar.** Top right is where iOS puts
/// the button that dismisses a sheet, and a `Finish` there was pressed as a way
/// out — marking a session with nothing filled in as trained. Finishing is not a
/// way out; it is a claim about what happened, and it belongs past the last set,
/// where a lifter arrives having made it. Leaving is the chevron, and leaving
/// changes nothing.
///
/// **What it depends on.** SwiftUI and `Spacing`. The section it draws is a list
/// section, so it is placed inside the same `List` as the exercises.
struct SessionFinishSection: View {

    /// Whether the session has been marked done, which decides which of the two
    /// shapes this draws.
    let isLogged: Bool
    var onFinish: () -> Void
    /// Takes a finished session back to unfinished. It is what makes reopening
    /// one mean anything — without it a mistaken tap is permanent, and this
    /// button exists because that tap happened.
    var onUnfinish: () -> Void

    var body: some View {
        Section {
            if isLogged {
                HStack(spacing: Spacing.standard) {
                    Label("Logged", systemImage: "checkmark.circle.fill")
                        .font(.barbellBody)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Mark as unfinished", action: onUnfinish)
                        .font(.barbellSupport)
                }
                .padding(.vertical, Spacing.tight)
            } else {
                Button(action: onFinish) {
                    Text("Finish")
                        .font(.barbellBody)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                }
                .accessibilityHint("Marks this session as logged")
            }
        } footer: {
            // Said only where it is still true. A lifter about to press this
            // should know it records the session rather than closes the screen —
            // which is exactly the distinction the toolbar failed to draw.
            if !isLogged {
                Text("Records this session as trained. Closing without it changes nothing.")
            }
        }
    }
}
