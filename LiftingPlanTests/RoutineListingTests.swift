import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Every block has to be findable, and every block has to be described without
/// anything being invented for it.
///
/// The tab used to draw one block — the newest — so the block before it became
/// unreachable the moment Claude sent a new one, with all of its logged sets
/// still in the record and still going out in the export. These tests guard the
/// three things that made the list possible: dating a block from its own weeks,
/// saying what it is without filling in what it does not have, and separating
/// the block being trained from the ones behind it without judging either.
@Suite("Routine listing")
struct RoutineListingTests {

    /// A fixed calendar, so a date range is the same sentence on every machine.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "UTC") else { return calendar }
        calendar.timeZone = zone
        return calendar
    }()

    private static let english = Locale(identifier: "en_US")

    // MARK: - What a block is called

    @Test("A block is called what it called itself")
    func titleIsTheStatedTitle() {
        let plan = TrainingPlan(title: "Autumn Strength", goal: "Squat 315")
        #expect(RoutineListing.title(of: plan) == "Autumn Strength")
    }

    @Test("An unnamed block is called what it is for")
    func titleFallsBackToGoal() {
        let plan = TrainingPlan(title: "", goal: "Squat 315")
        #expect(RoutineListing.title(of: plan) == "Squat 315")
    }

    @Test("A routine that stated neither is just a routine")
    func titleFallsBackToBlock() {
        #expect(RoutineListing.title(of: TrainingPlan(title: "", goal: "")) == "Routine")
    }

    // MARK: - The dates a card states

    @Test("A four-week block covers its start date and the twenty-seven days after it")
    func spanIsTheBlockItself() throws {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        let span = try #require(RoutineListing.span(of: plan, calendar: Self.utc))
        #expect(span.lowerBound == date(2026, 8, 17))
        #expect(span.upperBound == date(2026, 9, 13))
    }

    @Test("The dates name both ends of the block")
    func datesNameBothEnds() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        let dates = RoutineListing.dates(of: plan, calendar: Self.utc, locale: Self.english)
        #expect(dates.contains("Aug 17"))
        #expect(dates.contains("Sep 13"))
    }

    @Test("A block the record has closed is still dated by the days it covered")
    func closingABlockDoesNotUndateIt() throws {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        plan.completedAt = date(2026, 9, 14)
        let span = try #require(RoutineListing.span(of: plan, calendar: Self.utc))
        #expect(span.upperBound == date(2026, 9, 13))
    }

    @Test("A block with no weeks has no range, and says so rather than inventing one")
    func aBlockWithNoWeeksHasNoDates() {
        let plan = TrainingPlan(title: "Not written yet", startDate: date(2026, 8, 17))
        #expect(RoutineListing.span(of: plan, calendar: Self.utc) == nil)
        #expect(RoutineListing.dateRange(of: plan, calendar: Self.utc, locale: Self.english) == nil)
        #expect(RoutineListing.dates(of: plan, calendar: Self.utc, locale: Self.english)
            == "No dates yet")
    }

    // MARK: - Which block is the current one

    @Test("The open block is the current one")
    func openBlockIsCurrent() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2)
        #expect(RoutineListing.standing(of: plan) == .current)
    }

    @Test("A superseded block stands as earlier, and nothing is said about why it ended")
    func closedBlockIsEarlier() {
        let plan = plan(startingOn: date(2026, 5, 4), weeks: 2)
        plan.completedAt = date(2026, 8, 17)
        #expect(RoutineListing.standing(of: plan) == .earlier)
        // The record does not separate "finished" from "abandoned", so neither
        // does the list: it says where the block stands and stops.
        let said = RoutineListing.Standing.earlier.spoken
            + RoutineListing.subtitle(of: plan, calendar: Self.utc, locale: Self.english)
        for verdict in ["Complete", "Finished", "Abandoned", "Failed", "Missed"] {
            #expect(said.localizedCaseInsensitiveContains(verdict) == false)
        }
    }

    @Test("Each standing is said in a word, so no meaning rests on order alone")
    func standingsAreWords() {
        // The list has no headings and no glyph: a sighted lifter reads the
        // standing off the order and off what the row says. A screen reader
        // hears one row at a time, so the row carries the word itself.
        #expect(RoutineListing.Standing.current.spoken.contains("Current"))
        #expect(RoutineListing.Standing.earlier.spoken.contains("Earlier"))
    }

    // MARK: - What the card says

    @Test("A block states how many sessions it prescribes")
    func summaryCountsSessions() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3)
        #expect(RoutineListing.summary(of: plan) == "6 sessions")
    }

    @Test("A logged session is counted once there is one")
    func summaryCountsLoggedSessions() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3, logged: 2)
        #expect(RoutineListing.summary(of: plan) == "6 sessions · 2 logged")
    }

    @Test("A block nobody has trained yet does not report zero logged")
    func nothingLoggedIsNotZeroLogged() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 1, daysPerWeek: 1)
        #expect(RoutineListing.summary(of: plan) == "1 session")
    }

    @Test("A block with no sessions says so rather than counting to zero")
    func noSessionsIsNotZeroOfZero() {
        let plan = TrainingPlan(title: "Just arrived", startDate: date(2026, 8, 17))
        let summary = RoutineListing.summary(of: plan)
        #expect(summary == "No sessions yet")
        #expect(summary.contains("0") == false)
    }

    @Test("A block behind him is when it ran and how much of it was logged")
    func earlierSubtitleStatesDatesThenCounts() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3, logged: 2)
        plan.completedAt = date(2026, 9, 1)
        let subtitle = RoutineListing.subtitle(of: plan, calendar: Self.utc, locale: Self.english)
        #expect(subtitle.contains("Aug 17"))
        #expect(subtitle.hasSuffix("6 sessions · 2 logged"))
    }

    @Test("A block behind him that cannot be dated still says what it prescribed")
    func earlierSubtitleSurvivesMissingDates() {
        let plan = TrainingPlan(title: "Just arrived", startDate: date(2026, 8, 17))
        plan.completedAt = date(2026, 9, 1)
        #expect(RoutineListing.subtitle(of: plan, calendar: Self.utc, locale: Self.english)
            == "No dates yet · No sessions yet")
    }

    // MARK: - Where he is in the block he is training

    @Test("The block being trained says which week he is on and what is logged")
    func currentSubtitleStatesProgress() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 3, daysPerWeek: 3, logged: 4)
        #expect(RoutineListing.subtitle(of: plan, calendar: Self.utc, locale: Self.english)
            == "Block 2 of 3 · 4 of 9 logged")
    }

    @Test("The week is the earliest one still holding an unfinished session")
    func progressReadsTheWeekFromTheRecord() {
        // Not from the calendar: a block picked up a fortnight late is on the
        // week he has reached, not the week the date would put him on.
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 3, daysPerWeek: 3, logged: 3)
        #expect(RoutineListing.progress(of: plan).hasPrefix("Block 2 of 3"))
    }

    @Test("A block nobody has trained yet states its size rather than zero logged")
    func progressDoesNotReportZeroLogged() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3)
        let progress = RoutineListing.progress(of: plan)
        #expect(progress == "Block 1 of 2 · 6 sessions")
        #expect(progress.contains("0") == false)
    }

    @Test("A block with no weeks yet claims no week and no sessions")
    func progressSurvivesAnEmptyBlock() {
        let plan = TrainingPlan(title: "Just arrived", startDate: date(2026, 8, 17))
        #expect(RoutineListing.progress(of: plan) == "No sessions yet")
    }

    // MARK: - Fixtures

    private func plan(
        startingOn start: Date, weeks weekCount: Int, daysPerWeek: Int = 1, logged: Int = 0
    ) -> TrainingPlan {
        let plan = TrainingPlan(title: "Block", startDate: start, weekCount: weekCount)
        var remainingToLog = logged
        plan.weeks = (1...weekCount).map { ordinal in
            let week = TrainingWeek(ordinal: ordinal)
            week.days = Weekday.displayOrder.prefix(daysPerWeek).map { weekday in
                let isLogged = remainingToLog > 0
                if isLogged { remainingToLog -= 1 }
                return WorkoutDay(
                    weekday: weekday, focus: "Full Body",
                    completedAt: isLogged ? start : nil
                )
            }
            return week
        }
        return plan
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return Self.utc.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
