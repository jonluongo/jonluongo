import Foundation
import Observation
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

/// The between-sets pace timer. It counts down from an exercise's prescribed
/// rest so a casual lifter keeps a tight tempo instead of drifting. It is
/// date-based, so it is accurate across backgrounding, and it fires a haptic and
/// a sound at zero for the lifter who is looking at the screen.
///
/// **The half that has to reach a pocketed phone is `ScreenLockedCue`.** This
/// type owned that too — the notifications, the permission flow and the report
/// of why they could not be armed — which made one type responsible for a clock,
/// a system permission and an error message, three things that fail for
/// different reasons. It tells the cue when a rest starts and when it stops;
/// what the cue does with that, and what it says when it cannot, is the cue's.
///
/// **What it depends on.** `ScreenLockedCue` for the alert, and injected seams
/// for the clock and the in-hand alert so both can be tested without waiting or
/// listening.
@Observable
@MainActor
final class RestTimerModel {

    /// Seconds remaining, clamped at 0. `0` with `isRunning == false` means idle.
    private(set) var remaining: Int = 0
    /// The rest length the current countdown started from, for the progress ring.
    private(set) var total: Int = 0
    private(set) var isRunning = false
    /// What the lifter just finished, carried into the screen-locked cue —
    /// `Next up: Barbell Bench Press` — so the one moment he is not looking at
    /// the bar is the one moment he is told. The bar itself does not draw it:
    /// there is no room beside the controls, and on screen he already knows.
    private(set) var contextLabel: String = ""
    private var endDate: Date?
    private var ticker: Timer?
    /// The alert that has to reach him with the screen locked. Held rather than
    /// forwarded: a caller showing what went wrong asks the thing it went wrong
    /// in.
    let cue: ScreenLockedCue
    /// What time it is. Injected so a test can put the clock past the end of a
    /// rest without waiting for one — which is the only way to reach the state
    /// a suspended app comes back in.
    private let now: () -> Date
    /// The cue in his hand: haptic and sound. Injected for the same reason the
    /// clock is — whether it fires is the whole of what `finish` decides, and a
    /// system sound played straight into the speaker cannot be asked about.
    private let alert: @MainActor () -> Void

    /// The real notification centre by default; a fake in tests, which cannot
    /// ask a simulator for permission and must still be able to check that a
    /// refusal is reported rather than swallowed.
    init(
        cue: ScreenLockedCue = ScreenLockedCue(),
        now: @escaping () -> Date = Date.init,
        alert: @escaping @MainActor () -> Void = RestTimerModel.playInHandAlert
    ) {
        self.cue = cue
        self.now = now
        self.alert = alert
    }

    /// Fraction elapsed, 0...1 — drives the ring.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - remaining) / Double(total)))
    }

    var formattedRemaining: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Begin (or restart) a countdown of `seconds`, tied to a set the lifter just
    /// logged. The cue is armed for the same moment, and asks for permission
    /// itself the first time it is.
    func start(seconds: Int, context: String) {
        guard seconds > 0 else { return }
        total = seconds
        remaining = seconds
        contextLabel = context
        endDate = now().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        scheduleTicker()
        cue.arm(after: seconds, context: context)
    }

    /// Adjust a running timer by ±seconds (e.g. "+15" / "−15"), never below 1s.
    func addTime(_ seconds: Int) {
        guard isRunning, let current = endDate else {
            // Restart a short one if nothing is active.
            if seconds > 0 { start(seconds: seconds, context: contextLabel) }
            return
        }
        let minimumEnd = now().addingTimeInterval(1)
        let proposedEnd = current.addingTimeInterval(TimeInterval(seconds))
        endDate = max(proposedEnd, minimumEnd)
        recomputeRemaining()
        // Keep the ring's denominator consistent with the new length.
        total = max(remaining, total + seconds)
        cue.arm(after: remaining, context: contextLabel)
    }

    /// Skip the rest entirely and go idle.
    func skip() {
        stop()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        remaining = 0
        endDate = nil
        cue.cancel()
    }

    // MARK: - Ticking

    private func scheduleTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeRemaining() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Brings `remaining` up to date, and ends the rest once it has run out.
    ///
    /// Internal so a test can drive it: the ticker is a real `Timer`, and the
    /// state worth testing is the one where time has passed without it firing.
    func recomputeRemaining() {
        guard let endDate else { return }
        let secondsLeft = Int(ceil(endDate.timeIntervalSince(now())))
        if secondsLeft <= 0 {
            remaining = 0
            finish(overshoot: now().timeIntervalSince(endDate))
        } else {
            remaining = secondsLeft
        }
    }

    /// Ends the rest, sounding the in-hand cue only if it ended just now.
    ///
    /// **A suspended app comes back to a countdown that ran out while it was
    /// away.** The ticker is a run-loop timer, so it stops with the app and
    /// catches up on the next foreground — and firing the haptic and the ding
    /// there means alarming, in his hand, about a rest that ended ten minutes
    /// ago and has already been announced three times by the notifications. The
    /// cue is for the phone he is looking at; past `staleAfter` the screen-locked
    /// alerts have done the job and this stays quiet.
    private func finish(overshoot: TimeInterval) {
        guard isRunning else { return }
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        endDate = nil
        guard overshoot < Self.staleAfter else { return }
        alert()
    }

    /// How far past the end a rest can be and still be worth sounding in his
    /// hand. Longer than a tick, shorter than a walk back to the bar.
    private static let staleAfter: TimeInterval = 5

    // MARK: - Alerts

    /// Vibrate and play the standard alert sound, so the end of a rest is felt
    /// and heard by a lifter looking at the phone.
    @MainActor
    static func playInHandAlert() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1005)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

}
