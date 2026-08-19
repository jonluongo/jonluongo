import Foundation
import Observation
import AudioToolbox
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// The between-sets pace timer. It counts down from an exercise's prescribed rest
/// so a casual lifter keeps a tight tempo instead of drifting. It's date-based
/// (accurate across backgrounding) and fires a haptic, a sound, and a local
/// notification at zero so the cue lands even with the screen locked.
///
/// **The screen-locked half can fail, and says so when it does.** Permission
/// refused, permission never asked, notifications turned off in Settings — any
/// of these leaves the countdown running on screen while the cue that was
/// supposed to reach a pocketed phone never arrives. That failure used to be
/// discarded at both ends, which meant the one thing this type promises could
/// stop working permanently and silently. `errorMessage` holds what went wrong;
/// `RestTimerBar` shows it beside the countdown, where it costs nothing to read
/// and is in front of the lifter at the moment it matters.
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
    /// Why the screen-locked cue cannot fire, ready to show. `nil` when it can,
    /// or when nothing has been attempted yet.
    private(set) var errorMessage: String?

    private var endDate: Date?
    private var ticker: Timer?
    /// What each of the finish alerts is filed under, so a restarted timer
    /// cancels every one of them and not just the first.
    private static func notificationID(_ index: Int) -> String {
        "rest-timer-finished-\(index)"
    }
    private let center: any RestNotificationScheduling

    /// The real notification centre by default; a fake in tests, which cannot
    /// ask a simulator for permission and must still be able to check that a
    /// refusal is reported rather than swallowed.
    init(center: any RestNotificationScheduling = SystemRestNotificationCenter()) {
        self.center = center
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

    /// Ask for notification permission once, so the finish alert can fire in background.
    ///
    /// Both answers are kept. A thrown error is a failure to report; a plain
    /// refusal is the lifter's choice and not an error, but it does mean the
    /// screen-locked cue will not arrive, and letting him believe it will is the
    /// worse of the two. Either way the on-screen countdown is unaffected.
    func requestNotificationAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            errorMessage = granted ? nil : Self.refusedMessage
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Clears a reported failure, after the lifter has been shown it.
    func dismissError() {
        errorMessage = nil
    }

    private static let refusedMessage =
        "Notifications are off, so the rest timer can't alert you once the screen locks. "
            + "Turn them on in Settings if you want the cue in your pocket."

    private static func describe(_ error: any Error) -> String {
        let reason = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        return "The rest timer can't alert you once the screen locks: \(reason)"
    }

    /// Begin (or restart) a countdown of `seconds`, tied to a set the lifter just logged.
    func start(seconds: Int, context: String) {
        guard seconds > 0 else { return }
        total = seconds
        remaining = seconds
        contextLabel = context
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        scheduleTicker()
        scheduleFinishNotification(after: seconds, context: context)
    }

    /// Adjust a running timer by ±seconds (e.g. "+15" / "−15"), never below 1s.
    func addTime(_ seconds: Int) {
        guard isRunning, let current = endDate else {
            // Restart a short one if nothing is active.
            if seconds > 0 { start(seconds: seconds, context: contextLabel) }
            return
        }
        let minimumEnd = Date().addingTimeInterval(1)
        let proposedEnd = current.addingTimeInterval(TimeInterval(seconds))
        endDate = max(proposedEnd, minimumEnd)
        recomputeRemaining()
        // Keep the ring's denominator consistent with the new length.
        total = max(remaining, total + seconds)
        scheduleFinishNotification(after: remaining, context: contextLabel)
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
        cancelFinishNotification()
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

    private func recomputeRemaining() {
        guard let endDate else { return }
        let secondsLeft = Int(ceil(endDate.timeIntervalSinceNow))
        if secondsLeft <= 0 {
            remaining = 0
            finish()
        } else {
            remaining = secondsLeft
        }
    }

    private func finish() {
        guard isRunning else { return }
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        endDate = nil
        fireLocalAlert()
    }

    // MARK: - Alerts

    private func fireLocalAlert() {
        // Vibrate + play the standard alert sound so it's felt and heard mid-set.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1005)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Arms the screen-locked cue, and reports it if it could not be armed.
    ///
    /// The scheduling call is the one that knows whether the cue will actually
    /// fire — permission can be withdrawn in Settings long after it was granted
    /// — so its failure is what `errorMessage` carries. A successful arming
    /// clears a stale message, so a lifter who fixed it in Settings stops being
    /// told about it.
    private func scheduleFinishNotification(after seconds: Int, context: String) {
        cancelFinishNotification()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = context.isEmpty ? "Time for your next set." : "Next up: \(context)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        Task {
            do {
                // **It insists rather than pings.** One notification is a single
                // short sound, which a phone face-down on a bench between sets
                // is exactly as likely to miss as to hear. Three of them, a few
                // seconds apart, is the loudest a build without Apple's
                // critical-alert entitlement can be — that entitlement is what a
                // real alarm sound and overriding the ringer switch require, and
                // it is granted per app by Apple rather than switched on here.
                for (index, delay) in Self.alertDelays.enumerated() {
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: TimeInterval(seconds + delay), repeats: false)
                    try await center.add(UNNotificationRequest(
                        identifier: Self.notificationID(index), content: content,
                        trigger: trigger))
                }
                errorMessage = nil
            } catch {
                errorMessage = Self.describe(error)
            }
        }
    }

    /// When each of the finish alerts fires, in seconds past the end of the
    /// rest. Three, because the first is the one he misses.
    private static let alertDelays = [0, 4, 8]

    private func cancelFinishNotification() {
        center.removePendingRequests(
            withIdentifiers: Self.alertDelays.indices.map(Self.notificationID))
    }
}

/// The part of the notification centre the rest timer needs, and no more.
///
/// It exists so the timer depends on a protocol rather than on
/// `UNUserNotificationCenter` — a singleton that cannot be asked for permission
/// in a test, which is why the failure this seam exposes went unnoticed and
/// untested for as long as it did. Conform a fake to it to make arming the cue
/// fail on demand. Both calls are throwing: an authorization request and a
/// scheduling request each have a real failure, and each was previously
/// discarded.
///
/// Depends on: `UserNotifications`.
@MainActor
protocol RestNotificationScheduling {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

/// The real notification centre behind `RestNotificationScheduling`.
///
/// A thin forwarder and nothing else: every decision about what to do with a
/// failure belongs to `RestTimerModel`, which is the type that knows what the
/// failure costs. Depends on: `UNUserNotificationCenter`.
@MainActor
struct SystemRestNotificationCenter: RestNotificationScheduling {

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
