import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The words the front door says.
///
/// Every line the Today screen prints that is not a stored string is built
/// here, which is why it is built somewhere a test can read it: a plural, an
/// off-by-one in "in 3 days", or a deload week losing the one word that marks
/// it are all mistakes a screenshot hides and a string comparison does not.
@Suite("Today's phrasing")
struct TodayPhrasingTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Fixed, so the test asserts the phrasing rather than the machine.
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// 2026-03-02, a Monday.
    private static let monday = Date(timeIntervalSince1970: 1_772_409_600)

    private static func placement(
        _ ordinal: Int, of total: Int, label: String? = nil, isDeload: Bool = false
    ) -> WeekPlacement {
        WeekPlacement(
            ordinal: ordinal, totalWeeks: total,
            stated: label.map { WeekPlacement.StatedWeek(label: $0, isDeload: isDeload) }
        )
    }

    private static func day(
        _ weekday: Weekday, focus: String = "", daysFromMonday: Int = 0,
        progress: SessionProgress = .notStarted
    ) -> BlockDay {
        BlockDay(
            week: placement(1, of: 4), weekday: weekday, focus: focus,
            date: monday.addingTimeInterval(Double(daysFromMonday) * 86_400),
            progress: progress
        )
    }

    // MARK: - The week

    @Test("A week states its position, its length and its label")
    func weekLineStatesEverything() {
        #expect(TodayPhrasing.weekLine(Self.placement(2, of: 4, label: "Accumulation"))
            == "Week 2 of 4 · Accumulation")
    }

    @Test("A one-week block is not week 1 of 1")
    func singleWeekBlock() {
        #expect(TodayPhrasing.weekLine(Self.placement(1, of: 1)) == "Week 1")
    }

    @Test("A week the plan never stated says only where it sits")
    func weekWithNoStatement() {
        #expect(TodayPhrasing.weekLine(Self.placement(3, of: 4)) == "Week 3 of 4")
    }

    @Test("An unlabelled deload is still called one")
    func unlabelledDeload() {
        // The one thing worth knowing about week 4 is that it is a deload. A
        // plan that marked it without naming it must not lose that.
        #expect(TodayPhrasing.weekLine(Self.placement(4, of: 4, label: "", isDeload: true))
            == "Week 4 of 4 · Deload")
    }

    @Test("A label the plan wrote wins over the word Deload")
    func labelledDeload() {
        #expect(TodayPhrasing.weekLine(Self.placement(4, of: 4, label: "Taper", isDeload: true))
            == "Week 4 of 4 · Taper")
    }

    // MARK: - Today's session

    @Test("A session is called what the plan said it is for")
    func sessionTitleUsesFocus() {
        #expect(TodayPhrasing.sessionTitle(Self.day(.monday, focus: "Push")) == "Push")
    }

    @Test("A session the plan named nothing is called by its day")
    func sessionTitleFallsBackToWeekday() {
        #expect(TodayPhrasing.sessionTitle(Self.day(.monday)) == "Monday")
    }

    @Test("Where the lifter got to decides the word on the button")
    func actionTitleFollowsProgress() {
        #expect(TodayPhrasing.actionTitle(for: .notStarted) == "Start Session")
        #expect(TodayPhrasing.actionTitle(for: .inProgress) == "Resume Session")
        #expect(TodayPhrasing.actionTitle(for: .finished(Self.monday)) == nil)
    }

    // MARK: - What is next

    @Test("Tomorrow is called tomorrow, not by its weekday")
    func tomorrow() {
        let next = Self.day(.tuesday, focus: "Pull", daysFromMonday: 1)
        #expect(TodayPhrasing.nextLine(for: next, from: Self.monday, calendar: Self.calendar)
            == "Tomorrow · Pull")
    }

    @Test("A day later this week is named by its weekday")
    func laterThisWeek() {
        let next = Self.day(.thursday, focus: "Lower", daysFromMonday: 3)
        #expect(TodayPhrasing.nextLine(for: next, from: Self.monday, calendar: Self.calendar)
            == "Thursday · Lower")
    }

    @Test("Past a week a weekday would be ambiguous, so the count is stated")
    func beyondAWeek() {
        // "Thursday" eleven days out could be either of two Thursdays.
        let next = Self.day(.thursday, focus: "Lower", daysFromMonday: 10)
        #expect(TodayPhrasing.nextLine(for: next, from: Self.monday, calendar: Self.calendar)
            == "In 10 days · Lower")
    }

    @Test("A session the plan named nothing states only when it is")
    func nextWithoutFocus() {
        let next = Self.day(.tuesday, daysFromMonday: 1)
        #expect(TodayPhrasing.nextLine(for: next, from: Self.monday, calendar: Self.calendar)
            == "Tomorrow")
    }

    // MARK: - Before the block

    @Test("A block that has not begun says when it does")
    func startsIn() {
        #expect(TodayPhrasing.start(inDays: 1) == "Starts tomorrow")
        #expect(TodayPhrasing.start(inDays: 3) == "Starts in 3 days")
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
