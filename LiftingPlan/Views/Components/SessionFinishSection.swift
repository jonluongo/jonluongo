import SwiftUI

/// The end of a session being logged: the one control that changes what the
/// record says about it.
///
/// **What it does.** Draws the last section of the logging screen — `Finish` on
/// a session still open, and on a finished one the fact that it is finished
/// beside the way to take that back.
///
/// **A session with sets left greys the button and asks once.** It is never
/// disabled: whether he is finished is the user's to say, and a screen that
/// refuses to record three good sets because the plan wrote four is the app
/// making a training decision. So the colour says "not yet, surely?", the dialog
/// counts exactly what is left, and pressing through is one tap away.
///
/// **Why it is here rather than in the toolbar.** Top right is where iOS puts
/// the button that dismisses a sheet, and a `Finish` there was pressed as a way
/// out — marking a session with nothing filled in as trained. Finishing is not a
/// way out; it is a claim about what happened, and it belongs past the last set,
/// where a user arrives having made it. Leaving is the chevron, and leaving
/// changes nothing.
///
/// **It is the same button as Start.** Both are the one thing to do at their
/// point in the session, so they are drawn by `PrimaryActionButton` — the type
/// that exists because "Start workout", "Finish workout" and "Start 2min" had
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
    /// How many prescribed rows have not been ticked. Zero means the session is
    /// filled in; anything else greys the button and asks once before it is
    /// pressed. Neither prevents finishing.
    let unloggedSetCount: Int
    var onFinish: () -> Void
    /// Takes a finished session back to unfinished. It is what makes reopening
    /// one mean anything — without it a mistaken tap is permanent, and this
    /// button exists because that tap happened.
    var onUnfinish: () -> Void

    @State private var asking = false

    /// What the dialog asks, counting what is actually left rather than saying
    /// "some". A user who stopped one set short and one who stopped nine sets
    /// short are being asked different questions.
    private static func question(_ unlogged: Int) -> String {
        "\(unlogged) set\(unlogged == 1 ? "" : "s") not logged. Finish anyway?"
    }

    /// Bumped when a session is finished, so the haptic fires on the act rather
    /// than on the state — `isLogged` also flips when a plan arrives or the
    /// screen is rebuilt, and a phone that buzzes because a view redrew is worse
    /// than one that never buzzes.
    @State private var finishes = 0

    /// True for a beat after finishing, so the button confirms before it becomes
    /// the way back.
    ///
    /// **CLAUDE.md: an action keeps the same name through the whole flow.**
    /// *Finish workout* was pressed and the button immediately read *Mark as
    /// Unfinished* — an undo affordance, which is the one thing that cannot
    /// double as a confirmation. Nothing on the screen ever said the thing had
    /// happened, which is what *it sadly fades away* was describing.
    @State private var justFinished = false

    var body: some View {
        Section {
            // **One control, in one place, in both states.** The finished
            // state used to be a different object entirely — a mark, a word and
            // a text link sharing a panel — so the bottom of the screen changed
            // shape depending on what had happened there. It is the same button
            // in the same place now, saying what pressing it does; that a
            // session is logged is said by the record and by the panels above,
            // which are already on the recorded ground.
            PrimaryActionButton(
                title: justFinished
                    ? "Finished" : (isLogged ? "Mark as unfinished" : "Finish workout"),
                systemImage: justFinished
                    ? "checkmark" : (isLogged ? "arrow.uturn.backward" : "checkmark"),
                // Taking a session back is a correction, not an action the
                // screen is for, so it carries no fill at all. Finishing one
                // with sets unticked is a question rather than a refusal, so it
                // keeps the shape and loses the colour.
                prominence: justFinished
                    ? .recorded
                    : (isLogged ? .quiet : (unloggedSetCount > 0 ? .tentative : .primary)),
                action: {
                    // **The beat is a report, not a control.** `isLogged` is
                    // already true while it shows, so without this the button
                    // reading *Finished* called `onUnfinish()` — undoing, on the
                    // press, the exact thing it was confirming. The doc comment
                    // on `Prominence.recorded` claimed this behaviour before the
                    // code did it.
                    if justFinished { return }
                    if isLogged { return onUnfinish() }
                    if unloggedSetCount > 0 { asking = true } else { finish() }
                })
            .accessibilityHint(
                justFinished ? "This session is finished"
                    : (isLogged ? "Takes this session back to unfinished"
                        : "Marks this session as logged"))
            .confirmationDialog(
                Self.question(unloggedSetCount), isPresented: $asking,
                titleVisibility: .visible
            ) {
                Button("Finish workout") { finish() }
                Button("Keep going", role: .cancel) {}
            }
            // **The record arriving is the reward, so it is worth watching
            // arrive.** Finishing used to be a cut: the panels above were
            // suddenly on the recorded ground and the button was suddenly a
            // different word, with nothing between. The same change on a spring
            // reads as the session landing — and the haptic is `.success`,
            // which is the one iOS reserves for a thing completing.
            .sensoryFeedback(.success, trigger: finishes)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Spacing.major, leading: Spacing.section,
                bottom: Spacing.snug, trailing: Spacing.section))
        }
    }

    /// Finishes the session as one animated moment.
    ///
    /// The wash under every panel, the button's word and its fill all change on
    /// the same spring, so they read as one event rather than three redraws that
    /// happened to coincide. `onFinish` is the caller's write; the animation is
    /// this section's, because this is where the press happened.
    private func finish() {
        finishes += 1
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            onFinish()
            justFinished = true
        }
        // Long enough to read, short enough that it is a beat rather than a
        // state. The button is the way back after it, which is what a finished
        // session's control is for.
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.snappy) { justFinished = false }
        }
    }
}
