import SwiftUI

/// The bar along the bottom while a session is underway.
///
/// **It does not go away when the rest ends.** It used to appear on the first
/// tick and vanish on the last, so the one surface tying the app to the session
/// in progress blinked in and out between every set. It has two states now and
/// the axis between them is whether a clock is running: **resting** is the ring
/// counting down with ±15 and skip beside it; **between sets** is the session's
/// name and how long he has been training. Both open the same thing.
///
/// **And it survives leaving the session.** `RootView` draws it too, so the way
/// back into a workout is on screen wherever he wandered off to — which is what
/// makes a rest that outlives the screen reachable rather than an alarm with
/// nothing behind it.
///
/// It also carries the one thing the timer can fail at: if the screen-locked
/// cue could not be armed, the reason is shown here rather than logged and
/// forgotten. Tapping it dismisses it. An alert would be wrong — this is mid-set
/// and the countdown itself is working fine — but silence would be worse, since
/// the whole point of the notification is that the user is not looking.
struct RestTimerBar: View {
    var restTimer: RestTimerModel
    /// What the session is called, shown when no clock is running. Empty draws
    /// nothing rather than an empty line.
    var sessionTitle: String = ""
    /// When training began and when the last set landed, for the elapsed clock
    /// between sets. `nil` before anything has been logged.
    var startedAt: Date?
    var lastLoggedAt: Date?
    /// Opens the clock at full size. Only the ring and the word carry it: the
    /// three controls beside them are buttons of their own, and a button inside
    /// a button is a tap whose meaning depends on which one the system decides
    /// it hit.
    var onOpen: () -> Void = {}

    /// How far the bar sits from the edge of the screen.
    private static let barInset = Spacing.standard
    /// How far the bar's contents sit from the edge of the bar.
    private static let contentInset = Spacing.standard

    /// The error label sits above the bar and has to line up with what is
    /// inside it, so its inset is the sum of the two above rather than a
    /// hand-added total. It was written as `26`, which was `12 + 14` worked out
    /// once by hand: changing either of the two paddings moved the ring and
    /// left the label behind, with nothing to catch it.
    private static var errorInset: CGFloat { barInset + contentInset }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            if let errorMessage = restTimer.cue.errorMessage {
                Button { restTimer.cue.dismissError() } label: {
                    Label(errorMessage, systemImage: "bell.slash")
                        .font(.supersetSupport)
                        // Named for the reason the exercise menu's is: this sits
                        // inside a `Button`, where `.secondary` resolves against
                        // the tint rather than against the ink.
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Self.errorInset)
            }
            bar
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bar: some View {
        HStack(spacing: Spacing.standard) {
            glance
            if restTimer.isRunning { controls }
        }
        // **The bar is a panel like every other.** It was a material with a
        // hairline of its own and a sixteen-point shadow at eighteen per cent —
        // three times the weight of every panel on the screen behind it, and the
        // only surface in the app that was not `Palette.panel`. A floating thing
        // is still a thing that sits on the surface.
        .padding(.horizontal, Self.contentInset)
        .padding(.vertical, Spacing.snug)
        .panelSurface()
        .padding(.horizontal, Self.barInset)
        .padding(.bottom, Spacing.tight)
    }

    /// The left of the bar: the countdown while one is running, and what he is
    /// in the middle of when none is.
    private var glance: some View {
        HStack(spacing: Spacing.standard) {
            if restTimer.isRunning {
                TimerRing(
                    progress: restTimer.progress,
                    timeText: restTimer.formattedRemaining,
                    isRunning: true,
                    size: 52,
                    lineWidth: 5,
                    // Support rather than Metric: the countdown has to fit inside
                    // a 52pt ring, and "59:59" at Metric does not. What matters
                    // is that it is a text style at all, so it grows when the
                    // user's type does.
                    font: .supersetSupport
                )
            }

            // **The movement is not named here.** The ring, `−15`, `+15` and
            // skip take most of the bar, so the name arrived as
            // `Barbell Benc…` — a label naming nothing, in the one place the
            // user already knows the answer, because he ticked the set a
            // second ago. Inside a group it would be worse than useless: the
            // rest belongs to the round, not to whichever movement closed it.
            //
            // It is still carried by the notification, which is the case where
            // he is *not* looking at this screen and the name is the whole
            // point — `Next up: Barbell Bench Press`.
            //
            // Between sets there is room, and the question changes: not *how
            // long left* but *what am I in the middle of*. So the session's own
            // name goes here, with the elapsed clock under it.
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(restTimer.isRunning ? "Resting" : sessionTitle)
                    .font(.supersetTitle)
                    .foregroundStyle(Palette.ink)
                if !restTimer.isRunning, let startedAt, let lastLoggedAt {
                    SessionClock(
                        startedAt: startedAt, lastLoggedAt: lastLoggedAt, finishedAt: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Between sets the bar is a way back rather than a set of controls,
            // and nothing else on it says so.
            if !restTimer.isRunning {
                Image(systemName: "chevron.right")
                    .font(.supersetSupport)
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        // The glance is what opens the clock; the controls beside it are not
        // part of that tap.
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(
            restTimer.isRunning
                ? "Opens the rest clock and the next set"
                : "Returns to the workout")
    }

    private var controls: some View {
        HStack(spacing: Spacing.snug) {
            Button("−15") { restTimer.addTime(-15) }
            Button("+15") { restTimer.addTime(15) }
            Button {
                restTimer.skip()
            } label: {
                Label("Skip rest", systemImage: "forward.end.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)
        }
        .font(.supersetSupport)
        .fontWeight(.semibold)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Palette.rule)
        .foregroundStyle(Palette.ink)
    }
}
