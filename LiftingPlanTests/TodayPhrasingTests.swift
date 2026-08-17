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
        // A finished session still opens: a logged day used to be a dead end,
        // so a mis-tapped Finish or a weight typed wrong could not be put right.
        #expect(TodayPhrasing.actionTitle(for: .finished(Self.monday)) == "Open Session")
    }

    // MARK: - The day being shown

    // A *Next* section used to name the session after today, and these tests
    // covered its wording. The week strip says the same thing better — the next
    // training day is a marked column rather than a sentence — so the section
    // and its phrasing both went, and what the header says instead is below.

    @Test("The line names the weekday first, then the date")
    func dayLineNamesTheWeekday() {
        let line = TodayPhrasing.dayLine(
            Self.monday, locale: Locale(identifier: "en_US"), timeZone: .gmt)

        // Ordering is the locale's, so the parts are asserted rather than the
        // punctuation between them.
        #expect(line.contains("Monday"))
        #expect(line.contains("March"))
        #expect(line.contains("2"))
    }

    @Test("The year is not stated")
    func dayLineOmitsTheYear() {
        // It is the same for eleven months in twelve and the strip never
        // travels beyond one block, so it would be a word always there and
        // never read.
        let line = TodayPhrasing.dayLine(
            Self.monday, locale: Locale(identifier: "en_US"), timeZone: .gmt)

        #expect(!line.contains("2026"))
    }

    @Test("A different day gets a different line")
    func dayLineFollowsTheDay() {
        let monday = TodayPhrasing.dayLine(
            Self.monday, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        let tuesday = TodayPhrasing.dayLine(
            Self.monday.addingTimeInterval(86_400),
            locale: Locale(identifier: "en_US"), timeZone: .gmt)

        #expect(monday != tuesday)
        #expect(tuesday.contains("Tuesday"))
    }

    @Test("The day an instant falls on is the time zone's answer, not the machine's")
    func dayLineFollowsTheTimeZone() {
        // Midnight UTC on Monday is still Sunday evening in New York, and the
        // strip's circled column agrees with the line beneath it or neither can
        // be trusted.
        let utc = TodayPhrasing.dayLine(
            Self.monday, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        let newYork = TodayPhrasing.dayLine(
            Self.monday, locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "America/New_York") ?? .gmt)

        #expect(utc.contains("Monday"))
        #expect(newYork.contains("Sunday"))
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
