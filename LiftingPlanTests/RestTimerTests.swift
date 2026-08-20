import Testing
import Foundation
import UserNotifications
@testable import LiftingPlan

/// A notification centre that answers however a test needs it to.
///
/// The real one cannot be asked for permission in a test process, which is
/// exactly why the discarded authorization result went unnoticed for as long as
/// it did. Depends on: `RestNotificationScheduling`.
@MainActor
private final class FakeNotificationCenter: RestNotificationScheduling {
    var authorizationAnswer: Result<Bool, any Error> = .success(true)
    var schedulingError: (any Error)?
    private(set) var scheduled: [UNNotificationRequest] = []
    private(set) var removed: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try authorizationAnswer.get()
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let schedulingError { throw schedulingError }
        scheduled.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removed.append(contentsOf: identifiers)
    }
}

private struct NotificationsOff: LocalizedError {
    var errorDescription: String? { "Notifications are not allowed"}
}

@MainActor
@Suite("Rest timer math")
struct RestTimerTests {

    @Test("Starting seeds remaining, total, and running state")
    func start() {
        let timer = RestTimerModel()
        timer.start(seconds: 90, context: "Bench — set 2")
        #expect(timer.total == 90)
        #expect(timer.remaining == 90)
        #expect(timer.isRunning)
        #expect(timer.formattedRemaining == "1:30")
        #expect(timer.progress == 0)
        timer.stop()
    }

    @Test("Adding time extends the total")
    func addTime() {
        let timer = RestTimerModel()
        timer.start(seconds: 60, context: "Squat")
        timer.addTime(30)
        #expect(timer.total == 90)
        timer.stop()
    }

    @Test("Stopping resets to idle")
    func stop() {
        let timer = RestTimerModel()
        timer.start(seconds: 60, context: "Row")
        timer.stop()
        #expect(!timer.isRunning)
        #expect(timer.remaining == 0)
    }

    @Test("Formatting pads seconds")
    func formatting() {
        let timer = RestTimerModel()
        timer.start(seconds: 65, context: "")
        #expect(timer.formattedRemaining == "1:05")
        timer.stop()
    }
}

/// What happens to the half of this type that can actually fail.
///
/// The screen-locked cue is the whole reason the timer touches notifications at
/// all, and both of its failures were being thrown away — so it could stop
/// working permanently while the app said nothing.
@MainActor
@Suite("Rest timer notification failures")
struct RestTimerNotificationTests {

    @Test("A refused permission is reported rather than discarded")
    func refusedPermissionIsReported() async {
        let center = FakeNotificationCenter()
        center.authorizationAnswer = .success(false)
        let timer = RestTimerModel(center: center)

        await timer.requestNotificationAuthorization()

        let message = timer.errorMessage
        #expect(message?.contains("screen locks") == true)
    }

    @Test("A granted permission reports nothing")
    func grantedPermissionIsSilent() async {
        let timer = RestTimerModel(center: FakeNotificationCenter())

        await timer.requestNotificationAuthorization()

        #expect(timer.errorMessage == nil)
    }

    @Test("An error asking for permission is surfaced with its reason")
    func authorizationErrorIsSurfaced() async {
        let center = FakeNotificationCenter()
        center.authorizationAnswer = .failure(NotificationsOff())
        let timer = RestTimerModel(center: center)

        await timer.requestNotificationAuthorization()

        #expect(timer.errorMessage?.contains("Notifications are not allowed") == true)
    }

    @Test("A cue that could not be armed is reported, and dismissing clears it")
    func schedulingFailureIsReported() async throws {
        let center = FakeNotificationCenter()
        center.schedulingError = NotificationsOff()
        let timer = RestTimerModel(center: center)

        timer.start(seconds: 90, context: "Bench — set 2")
        try await Task.sleep(for: .milliseconds(50))
        timer.stop()

        #expect(timer.errorMessage?.contains("Notifications are not allowed") == true)
        timer.dismissError()
        #expect(timer.errorMessage == nil)
    }

    @Test("Arming the cue successfully clears a message from an earlier failure")
    func successClearsAStaleMessage() async throws {
        let center = FakeNotificationCenter()
        center.authorizationAnswer = .success(false)
        let timer = RestTimerModel(center: center)
        await timer.requestNotificationAuthorization()
        #expect(timer.errorMessage != nil)

        timer.start(seconds: 90, context: "Squat")
        try await Task.sleep(for: .milliseconds(50))
        timer.stop()

        #expect(timer.errorMessage == nil)
        // Three, a few seconds apart: one short sound is one a phone
        // face-down on a bench is as likely to miss as to hear.
        #expect(center.scheduled.count == 3)
    }

    @Test("A restarted timer cancels every alert of the one before it")
    func restartingCancelsAllThree() async throws {
        // Each alert is filed under its own identifier, so cancelling only the
        // first would leave two of them to fire against a countdown that no
        // longer exists.
        let center = FakeNotificationCenter()
        let timer = RestTimerModel(center: center)

        timer.start(seconds: 90, context: "Squat")
        try await Task.sleep(for: .milliseconds(50))
        timer.stop()

        #expect(Set(center.removed).count == 3)
    }

    // MARK: - Coming back to a rest that ran out while the app was away

    @Test("A rest that ended while the app was suspended does not ring in his hand")
    func aStaleFinishIsQuiet() throws {
        // The ticker is a run-loop timer, so it stops with the app and catches
        // up on the next foreground. Sounding the cue there is the app alarming
        // about a rest that ended ten minutes ago and was announced three times
        // by the notifications while he was away.
        let center = FakeNotificationCenter()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let alerts = AlertCounter()
        let timer = RestTimerModel(center: center, now: { clock }, alert: alerts.fire)

        timer.start(seconds: 90, context: "Squat")
        clock.addTimeInterval(600)
        timer.recomputeRemaining()

        #expect(!timer.isRunning)
        #expect(timer.remaining == 0)
        #expect(alerts.count == 0, "the notifications announced this while he was away")
    }

    @Test("A rest that ends while he is looking at it still ends")
    func aTimelyFinishStillEnds() throws {
        let center = FakeNotificationCenter()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let alerts = AlertCounter()
        let timer = RestTimerModel(center: center, now: { clock }, alert: alerts.fire)

        timer.start(seconds: 90, context: "Squat")
        clock.addTimeInterval(90)
        timer.recomputeRemaining()

        #expect(!timer.isRunning)
        #expect(timer.remaining == 0)
        #expect(alerts.count == 1, "he is looking at it, so it is felt and heard")
    }

    @Test("A running rest counts down against the clock, not against ticks")
    func remainingFollowsTheClock() throws {
        let center = FakeNotificationCenter()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let timer = RestTimerModel(center: center, now: { clock })

        timer.start(seconds: 180, context: "Bench")
        clock.addTimeInterval(60)
        timer.recomputeRemaining()

        #expect(timer.isRunning)
        #expect(timer.remaining == 120, "a minute away is a minute off the rest")
    }

    /// Counts the in-hand cue, which is otherwise a system sound nothing can
    /// ask about.
    @MainActor
    private final class AlertCounter {
        private(set) var count = 0
        func fire() { count += 1 }
    }
}
