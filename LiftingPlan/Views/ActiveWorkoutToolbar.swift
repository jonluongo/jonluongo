import SwiftUI
import UIKit

/// The chrome around a session being logged: how to leave it, and how long it
/// has been running.
///
/// **What it does.** Draws the three toolbar items the logging screen has — the
/// close control, the running time, and the keyboard's Done. It holds no state
/// and reaches into nothing: everything it needs it is handed, and everything it
/// does it reports.
///
/// **Top right closes, and closes is all it does.** It used to be `Finish`,
/// which is the position every sheet in iOS gives the button meaning *let me
/// out* — so it was pressed as one, and a session with nothing filled in came
/// back marked as trained. The answer was not to leave the corner empty: an
/// close control belongs where a reader's thumb already goes for it. Finishing
/// moved to the end of the session, under the last set, and the corner now holds
/// the only thing it was ever read as.
///
/// **How it is used.** `ActiveWorkoutView` passes it to `.toolbar`. It is a
/// `ToolbarContent` of its own rather than a computed property on that screen
/// because logging a set and framing the session are two jobs, and one file
/// doing both had grown past the point where either was easy to find.
///
/// **What it depends on.** SwiftUI, and `UIApplication` for dismissing the
/// keyboard.
struct ActiveWorkoutToolbar: ToolbarContent {

    /// When training began — the earliest ticked set — or `nil` while nothing
    /// has been ticked, which draws no clock at all.
    let startedAt: Date?
    /// When the session was marked done, which freezes the clock at what it
    /// took. A session reopened days later would otherwise report the time
    /// since, which is not a fact about the workout.
    let finishedAt: Date?
    var onClose: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        // Its own item, and nothing beside it. Sharing one with the clock gave
        // the toolbar a single background to draw around both, so the "circle"
        // was a capsule the width of glyph-plus-gap-plus-time and the glyph sat
        // at one end of it rather than in the middle of anything.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close workout")
        }
        // How long he has been training — the one thing worth a glance that
        // nothing else on the screen says.
        //
        // It carries no background of its own. A toolbar item is drawn in a
        // capsule now, which is the right shape for something that can be
        // pressed and a lie about something that cannot — the clock was reading
        // as a button nobody could work out the purpose of.
        //
        // It counts from the first ticked set rather than from the moment this
        // screen opened. Opening a screen is not training, and timing it meant
        // the clock restarted every time the session was closed and resumed.
        ToolbarItem(placement: .topBarLeading) {
            if let startedAt {
                if let finishedAt {
                    clock(Self.elapsed(from: startedAt, to: finishedAt))
                } else {
                    TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                        clock(Self.elapsed(from: startedAt, to: timeline.date))
                    }
                }
            }
        }
        .sharedBackgroundVisibility(.hidden)
        // There is no timer button here any more. Rest is prescribed per
        // exercise, so one control in the toolbar could not mean anything
        // specific — it opened a picker that started a stopwatch unrelated to
        // whatever set had just been logged. The rest line on each exercise's
        // card is the control now.
        //
        // A number pad has no return key, so without this the only way out of a
        // weight field is to scroll the list — which is a poor thing to require
        // of someone holding the phone in one hand between sets.
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { Self.dismissKeyboard() }
        }
    }

    private func clock(_ text: String) -> some View {
        Text(text)
            .font(.barbellSupport)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// The session's running time, as minutes and seconds.
    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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
