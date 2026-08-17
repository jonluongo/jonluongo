import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Every block has to be findable, and every block has to be described without
/// anything being invented for it.
///
/// The tab used to draw one plan — the newest — so the block before it became
/// unreachable the moment Claude sent a new one, with all of its logged sets
/// still in the record and still going out in the export. These tests guard the
/// two things that made the list possible: dating a block from its own weeks,
/// and saying what it is without filling in what it does not have.
@Suite("Plans listing")
struct PlansListingTests {

    /// A fixed calendar, so a date range is the same sentence on every machine.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "UTC") else { return calendar }
        calendar.timeZone = zone
        return calendar
    }()

    private static let english = Locale(identifier: "en_US")

    // MARK: - What a plan is called

    @Test("A plan is called what it called itself")
    func titleIsTheStatedTitle() {
        let plan = TrainingPlan(title: "Autumn Strength", goal: "Squat 315")
        #expect(PlansListing.title(of: plan) == "Autumn Strength")
    }

    @Test("An unnamed plan is called what it is for")
    func titleFallsBackToGoal() {
        let plan = TrainingPlan(title: "", goal: "Squat 315")
        #expect(PlansListing.title(of: plan) == "Squat 315")
    }

    @Test("A plan that stated neither is just a plan")
    func titleFallsBackToPlan() {
        #expect(PlansListing.title(of: TrainingPlan(title: "", goal: "")) == "Plan")
    }

    // MARK: - The dates a section is headed by

    @Test("A four-week block covers its start date and the twenty-seven days after it")
    func spanIsTheBlockItself() throws {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        let span = try #require(PlansListing.span(of: plan, calendar: Self.utc))
        #expect(span.lowerBound == date(2026, 8, 17))
        #expect(span.upperBound == date(2026, 9, 13))
    }

    @Test("The heading names both ends of the block")
    func headingNamesBothEnds() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        let heading = PlansListing.header(for: plan, calendar: Self.utc, locale: Self.english)
        #expect(heading.contains("Aug 17"))
        #expect(heading.contains("Sep 13"))
    }

    @Test("A block the record has closed is still dated by the days it covered")
    func closingABlockDoesNotUndateIt() throws {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 4)
        plan.completedAt = date(2026, 9, 14)
        let span = try #require(PlansListing.span(of: plan, calendar: Self.utc))
        #expect(span.upperBound == date(2026, 9, 13))
    }

    @Test("A block with no weeks has no range, and says so rather than inventing one")
    func aBlockWithNoWeeksHasNoDates() {
        let plan = TrainingPlan(title: "Not written yet", startDate: date(2026, 8, 17))
        #expect(PlansListing.span(of: plan, calendar: Self.utc) == nil)
        #expect(PlansListing.dateRange(of: plan, calendar: Self.utc, locale: Self.english) == nil)
        #expect(PlansListing.header(for: plan, calendar: Self.utc, locale: Self.english)
            == "No dates yet")
    }

    // MARK: - Which block is the current one

    @Test("The open block is the current one")
    func openBlockIsCurrent() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2)
        #expect(PlansListing.isCurrent(plan))
        #expect(PlansListing.summary(of: plan).hasPrefix("Current · "))
    }

    @Test("A superseded block is not current, and nothing is said about why it ended")
    func closedBlockIsNotCurrent() {
        let plan = plan(startingOn: date(2026, 5, 4), weeks: 2)
        plan.completedAt = date(2026, 8, 17)
        #expect(PlansListing.isCurrent(plan) == false)
        // The record does not separate "finished" from "superseded", so the
        // card does not either — it simply stops claiming to be current.
        #expect(PlansListing.summary(of: plan).contains("Current") == false)
    }

    // MARK: - What the card says

    @Test("A block states how many sessions it prescribes")
    func summaryCountsSessions() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3)
        #expect(PlansListing.summary(of: plan) == "Current · 6 sessions")
    }

    @Test("A logged session is counted once there is one")
    func summaryCountsLoggedSessions() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 2, daysPerWeek: 3, logged: 2)
        #expect(PlansListing.summary(of: plan) == "Current · 6 sessions · 2 logged")
    }

    @Test("A block nobody has trained yet does not report zero logged")
    func nothingLoggedIsNotZeroLogged() {
        let plan = plan(startingOn: date(2026, 8, 17), weeks: 1, daysPerWeek: 1)
        #expect(PlansListing.summary(of: plan) == "Current · 1 session")
    }

    @Test("A block with no sessions says so rather than counting to zero")
    func noSessionsIsNotZeroOfZero() {
        let plan = TrainingPlan(title: "Just arrived", startDate: date(2026, 8, 17))
        let summary = PlansListing.summary(of: plan)
        #expect(summary == "Current · No sessions yet")
        #expect(summary.contains("0") == false)
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
