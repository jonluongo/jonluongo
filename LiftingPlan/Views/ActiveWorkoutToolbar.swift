import SwiftUI
import UIKit

/// The chrome around a session being logged: how to leave it, and how long it
/// has been running.
///
/// **What it does.** Draws the three toolbar items the logging screen has — the
/// close chevron, the running time, and the keyboard's Done. It holds no state
/// and reaches into nothing: everything it needs it is handed, and everything it
/// does it reports.
///
/// **Finishing is not up here, and that is the point.** It was: `Finish` sat top
/// right, which is where every sheet in iOS puts the button that means *let me
/// out*. Tapping it to leave marked the day logged — a session with nothing
/// filled in read as trained, and the owner hit it on his first real session.
/// The one control that changes what the record says now lives at the end of the
/// session, under the last set, where a lifter arrives having actually finished.
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
        // was a capsule the width of chevron-plus-gap-plus-time and the chevron
        // sat at one end of it rather than in the middle of anything.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Close workout")
        }
        // How long he has been training — the one thing worth a glance that
        // nothing else on the screen says.
        //
        // It counts from the first ticked set rather than from the moment this
        // screen opened. Opening a screen is not training, and timing it meant
        // the clock restarted every time the session was closed and resumed.
        ToolbarItem(placement: .principal) {
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
        // There is no timer button here any more. Rest is prescribed per
        // exercise, so one control in the toolbar could not mean anything
        // specific — it opened a picker that started a stopwatch unrelated to
        // whatever set had just been logged. The rest line on each exercise's
        // card is the control now.
        //
        // Nothing sits top right. The chevron already leaves the session, and a
        // second control in the position that means *leave* was read as the way
        // out by the one person who has used this app — which is how a session
        // he had not started came to be marked as trained.
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
