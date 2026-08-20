import Testing
import Foundation
@testable import LiftingKit

/// The days a block covers, which is what dates a block the lifter is past.
///
/// It runs without a simulator, a database or a model, which is the whole
/// reason the derivation lives in `Domain/`. The fixtures force-unwrap
/// known-good date components and time zone identifiers, which the standard
/// permits inside tests and nowhere else.
///
/// This suite was three times the size, covering *where does today fall* —
/// which week, whether today trains, what is next. The app decided not to ask
/// (`docs/decided.md`), the front door that asked was deleted, and the answer
/// went with it.
@Suite("Routine calendar")
struct RoutineCalendarTests {

    @Test("A block covers its start date and seven days per week after it")
    func spanCoversEveryWeek() throws {
        let subject = RoutineCalendar(calendar: Self.utc)
        let span = try #require(subject.span(of: Self.fourWeekBlock()))

        #expect(span.lowerBound == Self.startOfDay(2026, 3, 2))
        // Four weeks from Monday 2 March ends on Sunday 29 March, not 30 March:
        // the last day is covered, and an off-by-one here is a day the block
        // would claim to run into for nothing.
        #expect(span.upperBound == Self.startOfDay(2026, 3, 29))
    }

    @Test("A gap in the ordinals is a week the plan left, not one to close up")
    func gapKeepsItsPlace() throws {
        // Weeks 1, 2 and 4 cover four weeks. Closing the gap would move the
        // last week a week earlier than the plan puts it.
        let subject = RoutineCalendar(calendar: Self.utc)
        let span = try #require(subject.span(
            of: RoutineSchedule(startDate: Self.at(2026, 3, 2), blockOrdinals: [1, 2, 4])))

        #expect(span.upperBound == Self.startOfDay(2026, 3, 29))
    }

    @Test("A block nothing dates has no extent")
    func undatedBlockHasNoSpan() {
        let subject = RoutineCalendar(calendar: Self.utc)

        #expect(subject.span(of: RoutineSchedule(startDate: nil, blockOrdinals: [])) == nil)
        #expect(subject.span(of: RoutineSchedule(startDate: nil, blockOrdinals: [1, 2])) == nil)
        // A start date with nothing to measure is no extent either — a block
        // with no weeks is not a block of one.
        #expect(subject.span(
            of: RoutineSchedule(startDate: Self.at(2026, 3, 2), blockOrdinals: [])) == nil)
    }

    @Test("The day rolls at the lifter's midnight, not at UTC's")
    func spanIsAnchoredInTheLiftersOwnDay() throws {
        // 23:00 UTC on 1 March is still 1 March in New York, so a block dated
        // then starts on the first there and on the second in UTC. Both ends
        // go through the calendar, so the whole range moves together.
        let newYork = Calendar.inNewYork
        let lateOnTheFirst = Self.at(2026, 3, 2, hour: 4)
        let span = try #require(RoutineCalendar(calendar: newYork).span(
            of: RoutineSchedule(startDate: lateOnTheFirst, blockOrdinals: [1])))

        #expect(span.lowerBound == Self.startOfDay(2026, 3, 1, in: newYork))
        #expect(span.upperBound == Self.startOfDay(2026, 3, 7, in: newYork))
    }

    @Test("A week that loses an hour to daylight saving is still seven days")
    func daylightSavingDoesNotShortenAWeek() throws {
        // 8 March 2026 is the spring-forward day in New York. Counted in
        // seconds the week would come up an hour short and land on the
        // Saturday; counted in days it lands on the Sunday, as every other
        // week does.
        let newYork = Calendar.inNewYork
        let span = try #require(RoutineCalendar(calendar: newYork).span(
            of: RoutineSchedule(
                startDate: Self.startOfDay(2026, 3, 2, in: newYork), blockOrdinals: [1])))

        #expect(span.upperBound == Self.startOfDay(2026, 3, 8, in: newYork))
    }

    // MARK: - Fixtures

    private static let utc = Calendar.inUTC

    private static func fourWeekBlock() -> RoutineSchedule {
        RoutineSchedule(startDate: at(2026, 3, 2), blockOrdinals: [1, 2, 3, 4])
    }

    private static func at(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in calendar: Calendar = utc
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        // swiftlint:disable:next force_unwrapping
        return calendar.date(from: components)!
    }

    private static func startOfDay(
        _ year: Int, _ month: Int, _ day: Int, in calendar: Calendar = utc
    ) -> Date {
        calendar.startOfDay(for: at(year, month, day, in: calendar))
    }
}

private extension Calendar {

    static var inUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static var inNewYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
}
