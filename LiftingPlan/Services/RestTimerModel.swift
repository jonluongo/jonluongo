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
@Observable
@MainActor
final class RestTimerModel {

    /// Seconds remaining, clamped at 0. `0` with `isRunning == false` means idle.
    private(set) var remaining: Int = 0
    /// The rest length the current countdown started from, for the progress ring.
    private(set) var total: Int = 0
    private(set) var isRunning = false
    /// Label of what the lifter just finished, shown under the timer.
    private(set) var contextLabel: String = ""

    private var endDate: Date?
    private var ticker: Timer?
    private let notificationID = "rest-timer-finished"

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
    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

    private func scheduleFinishNotification(after seconds: Int, context: String) {
        cancelFinishNotification()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = context.isEmpty ? "Time for your next set." : "Next up: \(context)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelFinishNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
