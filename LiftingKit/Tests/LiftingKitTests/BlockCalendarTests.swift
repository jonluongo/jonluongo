import Testing
import Foundation
@testable import LiftingKit

/// Nothing in the app knew what day it was: every week of a four-week block
/// rendered identically, and the lifter had to work out where they were.
///
/// This is the suite that closes that. It runs without a simulator, a database
/// or a model, which is the whole reason the derivation lives in `Domain/`.
///
/// The fixtures force-unwrap known-good date components and time zone
/// identifiers, which the standard permits inside tests and nowhere else.
@Suite("Block calendar")
struct BlockCalendarTests {

    // MARK: - Inside the block

    @Test("A training day mid-block reports its week, its weekday and its session")
    func trainingDayMidBlock() throws {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 11))

        let day = try #require(today.standing.session)
        #expect(day.week.ordinal == 2)
        #expect(day.week.totalWeeks == 4)
        #expect(day.week.stated?.label == "Accumulation")
        #expect(day.week.stated?.isDeload == false)
        #expect(day.weekday == .wednesday)
        #expect(day.focus == "Pull")
        #expect(day.progress == .notStarted)
        #expect(day.date == Self.startOfDay(2026, 3, 11))
        // What is next is answered even on a training day, because a session
        // finished at 6am leaves the rest of the day with a question.
        #expect(today.upcoming?.date == Self.startOfDay(2026, 3, 13))
    }

    @Test("A rest day mid-block is a state, not an absence, and names what is next")
    func restDayMidBlock() throws {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 10))

        let week = try #require(today.standing.rest)
        #expect(week.ordinal == 2)
        #expect(week.totalWeeks == 4)
        #expect(week.stated?.label == "Accumulation")

        let next = try #require(today.upcoming)
        #expect(next.weekday == .wednesday)
        #expect(next.week.ordinal == 2)
        #expect(next.date == Self.startOfDay(2026, 3, 11))
    }

    @Test("The first day of a block is week 1, not a block that has not begun")
    func firstDayOfBlock() throws {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 2))

        let day = try #require(today.standing.session)
        #expect(day.week.ordinal == 1)
        #expect(day.weekday == .monday)
        #expect(day.date == Self.startOfDay(2026, 3, 2))
    }

    @Test("The last prescribed session of a block has nothing after it")
    func lastSessionOfBlock() throws {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 27))

        let day = try #require(today.standing.session)
        #expect(day.week.ordinal == 4)
        #expect(day.week.stated?.isDeload == true)
        #expect(day.weekday == .friday)
        #expect(today.upcoming == nil)
    }

    @Test("The last covered day of a block is still inside it")
    func lastDayOfBlockIsARestDay() throws {
        // The block runs 28 days from Monday 2 March, so Sunday 29 March is the
        // last day it covers — a rest day, not a block that has run out.
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 29))

        let week = try #require(today.standing.rest)
        #expect(week.ordinal == 4)
        #expect(today.upcoming == nil)
    }

    // MARK: - Session progress

    @Test("A session with a set ticked is in progress")
    func sessionInProgress() throws {
        let schedule = Self.fourWeekBlock(
            progressFor: [.init(week: 2, weekday: .wednesday): .inProgress]
        )
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 11))

        let day = try #require(today.standing.session)
        #expect(day.progress == .inProgress)
        #expect(day.progress.isFinished == false)
    }

    @Test("A session already finished stays today's session and points past itself")
    func sessionAlreadyFinishedToday() throws {
        let finishedAt = Self.at(2026, 3, 11, hour: 6)
        let schedule = Self.fourWeekBlock(
            progressFor: [.init(week: 2, weekday: .wednesday): .finished(finishedAt)]
        )
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 11, hour: 20))

        let day = try #require(today.standing.session)
        #expect(day.progress == .finished(finishedAt))
        #expect(day.progress.isFinished)
        #expect(today.upcoming?.date == Self.startOfDay(2026, 3, 13))
    }

    @Test("What is next skips a session already finished ahead of time")
    func upcomingSkipsFinishedDays() {
        let schedule = Self.fourWeekBlock(
            progressFor: [
                .init(week: 2, weekday: .wednesday): .finished(Self.at(2026, 3, 9))
            ]
        )
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 10))

        #expect(today.upcoming?.date == Self.startOfDay(2026, 3, 13))
    }

    // MARK: - Outside the block

    @Test("A date before the block starts counts the days until it does")
    func beforeTheBlockStarts() {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 2, 28))

        #expect(today.standing == .beforeBlock(daysUntilStart: 2))
        #expect(today.upcoming?.date == Self.startOfDay(2026, 3, 2))
    }

    @Test("A date after the block ends reports the day it ran to")
    func afterTheBlockEnds() {
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: Self.fourWeekBlock(), on: Self.at(2026, 3, 30))

        #expect(today.standing == .elapsed(endedOn: Self.startOfDay(2026, 3, 29)))
        #expect(today.upcoming == nil)
    }

    @Test("A block the record has closed is closed, whatever the calendar says")
    func closedBlock() {
        let closed = Self.at(2026, 3, 20)
        let schedule = Self.fourWeekBlock(closedAt: closed)
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 25))

        // 25 March would otherwise be week 4's Wednesday session.
        #expect(today.standing == .closed(on: closed))
        #expect(today.upcoming == nil)
    }

    // MARK: - Absence

    @Test("A plan with no start date is undated, not started today")
    func noStartDate() {
        let schedule = BlockSchedule(startDate: nil, weeks: Self.fourWeekBlock().weeks)
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 11))

        #expect(today.standing == .undated)
        #expect(today.upcoming == nil)
    }

    @Test("A block with no weeks prescribes nothing to place today against")
    func noWeeks() {
        let schedule = BlockSchedule(startDate: Self.at(2026, 3, 2), weeks: [])
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 11))

        #expect(today.standing == .unscheduled)
        #expect(today.upcoming == nil)
    }

    // MARK: - Irregular blocks

    @Test("A gap in the week ordinals is a rest week, not a missing one")
    func weekGap() throws {
        let schedule = BlockSchedule(
            startDate: Self.at(2026, 3, 2),
            weeks: [
                ScheduledWeek(
                    ordinal: 1, label: "Base",
                    days: [ScheduledDay(weekday: .monday, focus: "Full Body")]),
                // No week 2 — the plan left the ordinal empty.
                ScheduledWeek(
                    ordinal: 3, label: "Return",
                    days: [ScheduledDay(weekday: .monday, focus: "Full Body")]),
            ]
        )
        let subject = BlockCalendar(calendar: Self.utc)
        let today = subject.today(in: schedule, on: Self.at(2026, 3, 9))

        let week = try #require(today.standing.rest)
        #expect(week.ordinal == 2)
        #expect(week.totalWeeks == 3)
        // A gap is not a week the plan named nothing — nothing was stated at all.
        #expect(week.stated == nil)
        #expect(today.upcoming?.date == Self.startOfDay(2026, 3, 16))
    }

    @Test("A block that trains weekends and starts midweek places every session")
    func unusualWeekdayPattern() throws {
        // Starts Wednesday and trains Saturday and Sunday only. Each week runs
        // seven days from the start date, so week 1 covers Wed 4 to Tue 10 and
        // its Saturday is 7 March.
        let weekend = [
            ScheduledDay(weekday: .saturday, focus: "Long"),
            ScheduledDay(weekday: .sunday, focus: "Easy"),
        ]
        let schedule = BlockSchedule(
            startDate: Self.at(2026, 3, 4),
            weeks: [
                ScheduledWeek(ordinal: 1, days: weekend),
                ScheduledWeek(ordinal: 2, days: weekend),
            ]
        )
        let subject = BlockCalendar(calendar: Self.utc)

        let saturday = subject.today(in: schedule, on: Self.at(2026, 3, 7))
        let first = try #require(saturday.standing.session)
        #expect(first.week.ordinal == 1)
        #expect(first.weekday == .saturday)
        #expect(saturday.upcoming?.date == Self.startOfDay(2026, 3, 8))

        // Wednesday 11 March is the first day of week 2, and a rest day.
        let wednesday = subject.today(in: schedule, on: Self.at(2026, 3, 11))
        let week = try #require(wednesday.standing.rest)
        #expect(week.ordinal == 2)
        #expect(wednesday.upcoming?.date == Self.startOfDay(2026, 3, 14))
    }

    // MARK: - Time zones

    @Test("The day rolls at the lifter's midnight, not at UTC's")
    func dayRollsAtLocalMidnight() throws {
        let newYork = Self.calendar(in: "America/New_York")
        let subject = BlockCalendar(calendar: newYork)
        let schedule = Self.fourWeekBlock(startedIn: newYork)

        // 23:00 on Wednesday in New York is already Thursday in UTC. The lifter
        // is still on Wednesday's session, and must be told so.
        let lateWednesday = Self.at(2026, 3, 11, hour: 23, in: newYork)
        let late = subject.today(in: schedule, on: lateWednesday)
        let day = try #require(late.standing.session)
        #expect(day.weekday == .wednesday)
        #expect(day.week.ordinal == 2)

        // Two hours later it is Thursday, and Thursday is a rest day.
        let earlyThursday = Self.at(2026, 3, 12, hour: 1, in: newYork)
        #expect(earlyThursday.timeIntervalSince(lateWednesday) == 7_200)
        let early = subject.today(in: schedule, on: earlyThursday)
        let week = try #require(early.standing.rest)
        #expect(week.ordinal == 2)
        #expect(early.upcoming?.weekday == .friday)
    }

    @Test("One wall-clock day is one answer, from a minute past midnight to a minute to")
    func oneDayIsOneAnswer() {
        let newYork = Self.calendar(in: "America/New_York")
        let subject = BlockCalendar(calendar: newYork)
        let schedule = Self.fourWeekBlock(startedIn: newYork)

        let justAfterMidnight = subject.today(
            in: schedule, on: Self.at(2026, 3, 11, hour: 0, minute: 1, in: newYork))
        let justBeforeMidnight = subject.today(
            in: schedule, on: Self.at(2026, 3, 11, hour: 23, minute: 59, in: newYork))
        #expect(justAfterMidnight == justBeforeMidnight)
    }

    @Test("A week that loses an hour to daylight saving is still seven days")
    func daylightSavingWeekIsStillSevenDays() throws {
        // US clocks go forward on Sunday 8 March 2026, inside week 1.
        let newYork = Self.calendar(in: "America/New_York")
        let subject = BlockCalendar(calendar: newYork)
        let schedule = Self.fourWeekBlock(startedIn: newYork)

        let today = subject.today(in: schedule, on: Self.at(2026, 3, 9, hour: 9, in: newYork))
        let day = try #require(today.standing.session)
        #expect(day.week.ordinal == 2)
        #expect(day.weekday == .monday)
        #expect(day.date == Self.startOfDay(2026, 3, 9, in: newYork))
    }

    // MARK: - Fixtures

    private static let utc = calendar(in: "UTC")

    private struct Slot: Hashable {
        let week: Int
        let weekday: Weekday
    }

    /// Four weeks from Monday 2 March 2026, training Monday, Wednesday and
    /// Friday, with week 4 marked as a deload.
    private static func fourWeekBlock(
        startedIn calendar: Calendar? = nil,
        closedAt: Date? = nil,
        progressFor progress: [Slot: SessionProgress] = [:]
    ) -> BlockSchedule {
        let start = at(2026, 3, 2, in: calendar ?? utc)
        let focuses: [Weekday: String] = [.monday: "Push", .wednesday: "Pull", .friday: "Legs"]
        let weeks = (1...4).map { ordinal in
            ScheduledWeek(
                ordinal: ordinal,
                label: ordinal == 4 ? "Deload" : "Accumulation",
                isDeload: ordinal == 4,
                days: [Weekday.monday, .wednesday, .friday].map { weekday in
                    ScheduledDay(
                        weekday: weekday,
                        focus: focuses[weekday] ?? "",
                        progress: progress[Slot(week: ordinal, weekday: weekday)] ?? .notStarted
                    )
                }
            )
        }
        return BlockSchedule(startDate: start, closedAt: closedAt, weeks: weeks)
    }

    private static func calendar(in identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private static func at(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0, in calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? utc
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private static func startOfDay(
        _ year: Int, _ month: Int, _ day: Int, in calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? utc
        return calendar.startOfDay(for: at(year, month, day, in: calendar))
    }
}
