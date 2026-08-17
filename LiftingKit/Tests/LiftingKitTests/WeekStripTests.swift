import Testing
import Foundation
@testable import LiftingKit

/// The seven columns the front door's header draws, and where a swipe lands.
///
/// The strip is the only part of the app that shows a day the lifter is *not*
/// standing in, so every one of its answers is one a glance takes on trust: the
/// wrong Sunday, a column that drifts on the week the clocks change, or a swipe
/// that walks off the end of a block are all mistakes a screenshot hides.
///
/// Runs without a simulator or a database, which is why the arithmetic lives in
/// `Domain/` rather than in the view that draws it.
///
/// The fixtures force-unwrap known-good date components and time zone
/// identifiers, which the standard permits inside tests and nowhere else.
@Suite("Week strip")
struct WeekStripTests {

    // MARK: - Which seven days

    @Test("The week is the lifter's calendar week, not seven days around today")
    func weekIsACalendarWeek() {
        // Wednesday 11 March 2026, in a locale whose weeks begin on Sunday.
        let days = WeekStrip(calendar: Self.sundayFirst).week(containing: Self.at(2026, 3, 11))

        #expect(days.count == 7)
        #expect(days.first == Self.startOfDay(2026, 3, 8))
        #expect(days.last == Self.startOfDay(2026, 3, 14))
    }

    @Test("A locale that starts its weeks on Monday gets a Monday-first strip")
    func firstWeekdayIsRespected() {
        let days = WeekStrip(calendar: Self.mondayFirst).week(containing: Self.at(2026, 3, 11))

        #expect(days.count == 7)
        #expect(days.first == Self.startOfDay(2026, 3, 9))
        #expect(days.last == Self.startOfDay(2026, 3, 15))
    }

    @Test("Every day of a week yields that same week, whichever one is asked about")
    func everyDayAgreesOnItsWeek() {
        let subject = WeekStrip(calendar: Self.sundayFirst)
        let expected = subject.week(containing: Self.at(2026, 3, 8))

        for day in 8...14 {
            #expect(subject.week(containing: Self.at(2026, 3, day)) == expected)
        }
    }

    @Test("Days are the starts of their days, so a late-evening date is still its own day")
    func daysAreStartsOfDays() {
        let subject = WeekStrip(calendar: Self.sundayFirst)
        let lateWednesday = subject.week(
            containing: Self.at(2026, 3, 11, hour: 23, minute: 59))

        #expect(lateWednesday == subject.week(containing: Self.at(2026, 3, 11)))
        #expect(lateWednesday.contains(Self.startOfDay(2026, 3, 11)))
    }

    @Test("The week the clocks go forward is still seven distinct days")
    func daylightSavingWeekIsSevenDays() {
        // US clocks go forward on Sunday 8 March 2026 — the first day of this
        // strip's week, which is where an hour of arithmetic would go missing.
        let newYork = Self.calendar(in: "America/New_York", firstWeekday: 1)
        let days = WeekStrip(calendar: newYork).week(
            containing: Self.at(2026, 3, 11, in: newYork))

        #expect(days.count == 7)
        #expect(Set(days).count == 7)
        #expect(days.first == Self.startOfDay(2026, 3, 8, in: newYork))
        #expect(days.last == Self.startOfDay(2026, 3, 14, in: newYork))
    }

    // MARK: - Where a swipe lands

    @Test("A swipe moves one day")
    func swipeMovesOneDay() {
        let subject = WeekStrip(calendar: Self.sundayFirst)

        #expect(subject.day(Self.at(2026, 3, 11), steppedBy: 1, within: Self.march)
            == Self.startOfDay(2026, 3, 12))
        #expect(subject.day(Self.at(2026, 3, 11), steppedBy: -1, within: Self.march)
            == Self.startOfDay(2026, 3, 10))
    }

    @Test("Swiping off the end of a week moves into the next one")
    func swipingCrossesIntoTheNextWeek() throws {
        let subject = WeekStrip(calendar: Self.sundayFirst)

        // Saturday is the last column of a Sunday-first week.
        let sunday = try #require(
            subject.day(Self.at(2026, 3, 14), steppedBy: 1, within: Self.march))
        #expect(sunday == Self.startOfDay(2026, 3, 15))
        // ...and the strip drawn around it is the following week, not the one
        // just left.
        #expect(subject.week(containing: sunday).first == Self.startOfDay(2026, 3, 15))
    }

    @Test("A swipe past the end of the range has nowhere to go")
    func swipeStopsAtTheEnd() {
        let subject = WeekStrip(calendar: Self.sundayFirst)

        // Nothing is clamped: landing one day short of what was asked would put
        // the lifter on a day he did not choose.
        #expect(subject.day(Self.at(2026, 3, 29), steppedBy: 1, within: Self.march) == nil)
        #expect(subject.day(Self.at(2026, 3, 2), steppedBy: -1, within: Self.march) == nil)
    }

    @Test("The ends of the range are themselves reachable")
    func endsOfTheRangeAreReachable() {
        let subject = WeekStrip(calendar: Self.sundayFirst)

        #expect(subject.day(Self.at(2026, 3, 28), steppedBy: 1, within: Self.march)
            == Self.startOfDay(2026, 3, 29))
        #expect(subject.day(Self.at(2026, 3, 3), steppedBy: -1, within: Self.march)
            == Self.startOfDay(2026, 3, 2))
    }

    @Test("A range stated with times still admits the whole of its first and last day")
    func rangeIsComparedByDay() {
        let subject = WeekStrip(calendar: Self.sundayFirst)
        let midMorningToMidMorning =
            Self.at(2026, 3, 2, hour: 9)...Self.at(2026, 3, 29, hour: 9)

        #expect(subject.day(Self.at(2026, 3, 3), steppedBy: -1, within: midMorningToMidMorning)
            == Self.startOfDay(2026, 3, 2))
        #expect(subject.day(Self.at(2026, 3, 28), steppedBy: 1, within: midMorningToMidMorning)
            == Self.startOfDay(2026, 3, 29))
    }

    @Test("A swipe across the clocks going forward moves a day, not twenty-three hours")
    func swipeAcrossDaylightSaving() {
        let newYork = Self.calendar(in: "America/New_York", firstWeekday: 1)
        let subject = WeekStrip(calendar: newYork)
        let first = Self.startOfDay(2026, 3, 2, in: newYork)
        let last = Self.startOfDay(2026, 3, 29, in: newYork)
        let march = first...last

        // Saturday the 7th into the Sunday the clocks change.
        #expect(subject.day(Self.at(2026, 3, 7, in: newYork), steppedBy: 1, within: march)
            == Self.startOfDay(2026, 3, 8, in: newYork))
    }

    // MARK: - Fixtures

    /// Monday 2 March to Sunday 29 March 2026 — four weeks, the length of the
    /// block the other suites use.
    private static let march = startOfDay(2026, 3, 2)...startOfDay(2026, 3, 29)

    private static let sundayFirst = calendar(in: "UTC", firstWeekday: 1)
    private static let mondayFirst = calendar(in: "UTC", firstWeekday: 2)

    private static func calendar(in identifier: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        // Stated rather than inherited, so the test asserts the strip's rule
        // instead of the machine's locale.
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func at(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0, in calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? sundayFirst
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone, year: year, month: month, day: day,
                hour: hour, minute: minute)
        )!
    }

    private static func startOfDay(
        _ year: Int, _ month: Int, _ day: Int, in calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? sundayFirst
        return calendar.startOfDay(for: at(year, month, day, in: calendar))
    }
}
