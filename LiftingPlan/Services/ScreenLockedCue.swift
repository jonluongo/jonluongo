import Foundation
import Observation
import UserNotifications

/// The half of the rest timer that has to reach a pocketed phone.
///
/// **What it does.** Arms the notifications that fire when a rest runs out, asks
/// for permission the first time one is armed, and keeps what went wrong when
/// they cannot be armed at all. It counts nothing and knows no rest length: it
/// is told how many seconds from now to fire and what to say.
///
/// **How it is used.** `RestTimerModel` owns one and calls `arm(after:context:)`
/// when a countdown starts or changes length, and `cancel()` when it stops.
/// `RestTimerBar` reads `errorMessage` and calls `dismissError()` once the
/// user has seen it.
///
/// **Why it is not part of the timer.** They fail independently and for
/// different reasons. The countdown on screen cannot fail; this can, permanently
/// and silently — permission refused, permission never asked, notifications
/// turned off in Settings long after they were granted. Keeping them together
/// meant one type owned a clock, a permission flow and an error report, and the
/// only one of the three with a seam for testing was this one. The seam was
/// already here; the split just puts the rest of it on the same side.
///
/// **What it depends on.** `RestNotificationScheduling`, which is the part of
/// `UNUserNotificationCenter` this needs and no more.
@Observable
@MainActor
final class ScreenLockedCue {

    /// Why the cue cannot fire, ready to show. `nil` when it can, or when
    /// nothing has been attempted yet.
    private(set) var errorMessage: String?

    private let center: any RestNotificationScheduling

    /// Whether permission has been asked for in this run. iOS prompts once per
    /// install; this stops the app asking it again every set.
    private var hasAsked = false

    /// The real notification centre by default; a fake in tests, which cannot
    /// ask a simulator for permission and must still be able to check that a
    /// refusal is reported rather than swallowed.
    init(center: any RestNotificationScheduling = SystemRestNotificationCenter()) {
        self.center = center
    }

    /// Arms the cue for `seconds` from now, and reports it if it could not be
    /// armed.
    ///
    /// **The first rest is when permission is asked for.** It used to be asked
    /// at launch, in front of an empty app: a dialog about alerts for a
    /// countdown that had never run, on a screen that says he has no routine.
    /// iOS gives one chance at that question, and *Don't Allow* there costs him
    /// the cue he would actually have wanted. Here it arrives with its answer in
    /// view — the clock has just started, and the alert is what tells him it
    /// finished while his phone is in his pocket.
    func arm(after seconds: Int, context: String) {
        if !hasAsked {
            hasAsked = true
            Task { await requestAuthorization() }
        }
        cancel()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = context.isEmpty ? "Time for your next set." : "Next up: \(context)"
        content.sound = .default
        // Asks to break through a Focus. **The app is not entitled to it**, so
        // iOS files it as an ordinary active alert: Time Sensitive Notifications
        // is a capability granted per App ID in the developer portal, and a
        // build that claims the entitlement without it is refused at signing —
        // checked, not assumed. Left stated because it is what this alert is,
        // and the day the capability is turned on it starts being honoured with
        // no code change.
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
                // **Scheduling succeeding is not the cue being able to fire.**
                // iOS accepts these requests from an app it will never display
                // one for, so clearing the message here told a user with
                // notifications off that all was well from his second rest
                // onward. Asked rather than assumed — which also means a user
                // who fixed it in Settings stops being told, and one who turned
                // them off months ago starts being told again.
                errorMessage = await center.allowsAlerts() ? nil : Self.refusedMessage
            } catch {
                errorMessage = Self.describe(error)
            }
        }
    }

    /// Takes the armed alerts back down, so a restarted or skipped rest does not
    /// fire the one it replaced.
    func cancel() {
        center.removePendingRequests(
            withIdentifiers: Self.alertDelays.indices.map(Self.notificationID))
    }

    /// Ask for notification permission, so the finish alert can fire in
    /// background.
    ///
    /// Both answers are kept. A thrown error is a failure to report; a plain
    /// refusal is the user's choice and not an error, but it does mean the
    /// cue will not arrive, and letting him believe it will is the worse of the
    /// two. Either way the on-screen countdown is unaffected.
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            errorMessage = granted ? nil : Self.refusedMessage
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Clears a reported failure, after the user has been shown it.
    func dismissError() {
        errorMessage = nil
    }

    /// When each of the finish alerts fires, in seconds past the end of the
    /// rest. Three, because the first is the one he misses.
    private static let alertDelays = [0, 4, 8]

    /// What each of the finish alerts is filed under, so a restarted timer
    /// cancels every one of them and not just the first.
    private static func notificationID(_ index: Int) -> String {
        "rest-timer-finished-\(index)"
    }

    private static let refusedMessage =
        "Notifications are off, so the rest timer can't alert you once the screen locks. "
            + "Turn them on in Settings if you want the cue in your pocket."

    private static func describe(_ error: any Error) -> String {
        let reason = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        return "The rest timer can't alert you once the screen locks: \(reason)"
    }
}

/// The part of the notification centre the cue needs, and no more.
///
/// It exists so the cue depends on a protocol rather than on
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
    /// Whether an alert armed right now would actually be shown.
    ///
    /// A separate question from what `requestAuthorization` answered, and the
    /// one that matters: iOS accepts a notification request from an app it will
    /// never display one for, so scheduling succeeding says nothing about
    /// whether the cue can fire. It is asked again on every arming because the
    /// answer changes in Settings, months later, without the app being told.
    func allowsAlerts() async -> Bool

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

/// The real notification centre behind `RestNotificationScheduling`.
///
/// A thin forwarder and nothing else: every decision about what to do with a
/// failure belongs to `ScreenLockedCue`, which is the type that knows what the
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

    /// Provisional counts: a quiet delivery still reaches the lock screen, which
    /// is the whole of what this cue promises.
    func allowsAlerts() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        return status == .authorized || status == .provisional
    }
}
