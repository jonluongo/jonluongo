import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The words the front door says.
///
/// Every line the Home screen prints that is not a stored string is built here,
/// which is why it is built somewhere a test can read it: a plural, or a button
/// that describes a screen instead of naming an action, are mistakes a
/// screenshot hides and a string comparison does not.
///
/// The week strip's phrasing used to be tested here too — a day line, a week
/// line, and how many days until a block began. Home has no calendar on it any
/// more, so all three went with the screen that printed them.
@Suite("Home phrasing")
struct TodayPhrasingTests {

    /// 2026-03-02, a Monday.
    private static let monday = Date(timeIntervalSince1970: 1_772_409_600)

    // MARK: - The workout

    @Test("A session is called what the plan said it is for")
    func sessionTitleUsesFocus() {
        #expect(TodayPhrasing.sessionTitle(focus: "Push", weekday: .monday) == "Push")
    }

    @Test("A session the plan named nothing is called by its day")
    func sessionTitleFallsBackToWeekday() {
        #expect(TodayPhrasing.sessionTitle(focus: "", weekday: .monday) == "Monday")
    }

    @Test("Every word on the button is something to do")
    func actionTitleFollowsProgress() {
        #expect(TodayPhrasing.actionTitle(for: .notStarted) == "Start Workout")
        #expect(TodayPhrasing.actionTitle(for: .inProgress) == "Continue Workout")
        // A finished session still opens: a logged day used to be a dead end, so
        // a mis-tapped Finish or a weight typed wrong could not be put right. It
        // said "Open Session", which names a screen rather than an action —
        // going back into either one is continuing the workout.
        #expect(TodayPhrasing.actionTitle(for: .finished(Self.monday)) == "Continue Workout")
    }

    // MARK: - Counts

    @Test("One exercise is not one exercises")
    func sessionShapePlurals() {
        #expect(TodayPhrasing.sessionShape(exercises: 1, durationMinutes: nil) == "1 exercise")
        #expect(TodayPhrasing.sessionShape(exercises: 5, durationMinutes: 45)
            == "5 exercises · 45 min")
    }

    @Test("A session with nothing in it claims nothing")
    func emptySessionShape() {
        #expect(TodayPhrasing.sessionShape(exercises: 0, durationMinutes: 45) == nil)
    }

    @Test("A finished block states what the record holds")
    func recordLine() {
        #expect(TodayPhrasing.recordLine(finished: 12, prescribed: 14) == "12 of 14 sessions logged")
    }

    @Test("A block that prescribed nothing states nothing")
    func emptyRecordLine() {
        // Not "0 of 0", which reads as a failure at something nobody asked for.
        #expect(TodayPhrasing.recordLine(finished: 0, prescribed: 0) == nil)
    }
}
