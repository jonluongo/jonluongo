import SwiftUI
import UIKit

/// The chrome around a session being logged: how to leave it, how long it has
/// been running, and the one action that ends it.
///
/// **What it does.** Draws the four toolbar items the logging screen has — the
/// close chevron, the running time, the action whose word says which state the
/// session is in, and the keyboard's Done. It holds no state and reaches into
/// nothing: everything it needs it is handed, and everything it does it reports.
///
/// **How it is used.** `ActiveWorkoutView` passes it to `.toolbar`. It is a
/// `ToolbarContent` of its own rather than a computed property on that screen
/// because logging a set and framing the session are two jobs, and one file
/// doing both had grown past the point where either was easy to find.
///
/// **What it depends on.** SwiftUI, and `UIApplication` for dismissing the
/// keyboard.
struct ActiveWorkoutToolbar: ToolbarContent {

    /// When the lifter opened the session; the clock counts up from here.
    let startDate: Date
    /// Whether the session has been marked done, which decides what the one
    /// action is called.
    let isLogged: Bool
    var onClose: () -> Void
    var onFinish: () -> Void
    /// Takes a finished session back to unfinished — the rare correction, which
    /// is why it sits in a menu rather than on the surface.
    var onUnfinish: () -> Void

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
        // The session's running time, where the focus used to be. The focus was
        // removed as unhelpful — the lifter picked this session and is looking
        // at its exercises — and how long he has been training is the one thing
        // worth a glance that nothing else on the screen says.
        ToolbarItem(placement: .principal) {
            TimelineView(.periodic(from: startDate, by: 1)) { timeline in
                Text(Self.elapsed(from: startDate, to: timeline.date))
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        // There is no timer button here any more. Rest is prescribed per
        // exercise, so one control in the toolbar could not mean anything
        // specific — it opened a picker that started a stopwatch unrelated to
        // whatever set had just been logged. The rest line on each exercise's
        // card is the control now.
        // One action, and its word says which state the session is in. A
        // logged session is already recorded, so the button only closes it —
        // calling that "Finish" would ask the lifter to finish something that
        // is finished. Un-finishing is the rare correction, so it sits in the
        // menu rather than on the surface: it is what makes reopening mean
        // anything, and it is not what anyone came here to press.
        ToolbarItem(placement: .topBarTrailing) {
            if isLogged {
                Menu {
                    Button("Mark as unfinished", systemImage: "arrow.uturn.backward") {
                        onUnfinish()
                    }
                } label: {
                    Text("Done").fontWeight(.semibold)
                } primaryAction: {
                    onClose()
                }
            } else {
                Button("Finish") { onFinish() }
                    .fontWeight(.semibold)
            }
        }
        // A number pad has no return key, so without this the only way out of a
        // weight field is to scroll the list — which is a poor thing to require
        // of someone holding the phone in one hand between sets.
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { Self.dismissKeyboard() }
        }
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
