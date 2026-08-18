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

    @Test("A session nobody has touched says nothing about its progress")
    func untouchedSessionSaysNothing() {
        // The ordinary case. A card that printed "Not started" would be telling
        // him what he already knows on every session he has not begun.
        #expect(TodayPhrasing.progressNote(for: .notStarted) == nil)
    }

    @Test("A session under way and one already logged each say which")
    func progressNoteReportsWhereHeGotTo() {
        #expect(TodayPhrasing.progressNote(for: .inProgress) == "In progress")
        // Reported, not concluded: a logged session is still open to correction,
        // so nothing here says he is finished with it.
        #expect(TodayPhrasing.progressNote(for: .finished(Self.monday)) == "Logged")
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
