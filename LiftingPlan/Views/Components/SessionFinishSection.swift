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
/// **It is the same button as Start.** Both are the one thing to do at their
/// point in the session, so they are drawn by `PrimaryActionButton` — the type
/// that exists because "Start Workout", "Finish Workout" and "Start 2min" had
/// once drifted into three buttons of different heights and colours. This
/// section first drew a hand-rolled one, which was that drift happening again.
/// It carries the accent, not green: green marks what the record already holds
/// — a ticked set, a logged session — and this button is the act that creates
/// that, not the fact itself.
///
/// **What it depends on.** SwiftUI, `Spacing` and `PrimaryActionButton`. The
/// section it draws is a list section, so it is placed inside the same `List` as
/// the exercises; its rows carry no card behind them, because a button is not a
/// row of a table.
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
                .listRowBackground(Color.clear)
            } else {
                PrimaryActionButton(
                    title: "Finish Workout", systemImage: "checkmark", action: onFinish)
                .accessibilityHint("Marks this session as logged")
                .listRowBackground(Color.clear)
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
