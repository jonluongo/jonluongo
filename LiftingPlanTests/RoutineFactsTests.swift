import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What the routine sheet states about a plan's shape.
///
/// The rule under every case here is the one the whole record runs on: a fact
/// the plan did not state is absent, never zero. A routine that never said how
/// long a session runs has not said it runs for no time.
@Suite("Routine facts")
@MainActor
struct RoutineFactsTests {

    private func makePlan(
        blocks: Int = 0, daysPerBlock: Int = 0, logged: Int = 0,
        weekdays: Set<Weekday> = [], durationMinutes: Int? = nil
    ) -> TrainingPlan {
        let plan = TrainingPlan(
            title: "Test", weekdays: weekdays, durationMinutes: durationMinutes)
        var remainingLogged = logged
        plan.weeks = (0..<blocks).map { ordinal in
            let week = TrainingWeek(ordinal: ordinal + 1)
            week.days = (0..<daysPerBlock).map { _ in
                let day = WorkoutDay(weekday: .monday)
                if remainingLogged > 0 {
                    day.completedAt = Date()
                    remainingLogged -= 1
                }
                return day
            }
            return week
        }
        return plan
    }

    private func value(_ label: String, in plan: TrainingPlan) -> String? {
        RoutineFacts.facts(of: plan).first { $0.label == label }?.value
    }

    @Test("A plan states what it holds and how much of it is logged")
    func countsWhatIsThere() {
        let plan = makePlan(blocks: 4, daysPerBlock: 3, logged: 5)
        #expect(value("Blocks", in: plan) == "4")
        #expect(value("Sessions", in: plan) == "12")
        #expect(value("Logged", in: plan) == "5")
    }

    @Test("A plan with nothing in it states nothing, rather than a page of noughts")
    func emptyPlanStatesNothing() {
        #expect(RoutineFacts.facts(of: makePlan()).isEmpty)
    }

    @Test("Sessions none of which are logged still state a logged count of none")
    func nothingLoggedIsStillACount() {
        // Distinct from the case above: there are sessions, and none are done.
        // That is a fact somebody can act on, unlike the absence of sessions.
        let plan = makePlan(blocks: 1, daysPerBlock: 3)
        #expect(value("Sessions", in: plan) == "3")
        #expect(value("Logged", in: plan) == "0")
    }

    @Test("A session length nobody stated is absent, not zero minutes")
    func unstatedLengthIsAbsent() {
        #expect(value("Session length", in: makePlan(blocks: 1, daysPerBlock: 1)) == nil)
        #expect(
            value("Session length", in: makePlan(blocks: 1, daysPerBlock: 1, durationMinutes: 45))
                == "45 min")
    }

    @Test("Training days are stated in week order, short")
    func trainingDaysReadInOrder() {
        let plan = makePlan(blocks: 1, daysPerBlock: 1, weekdays: [.friday, .monday, .wednesday])
        #expect(value("Training days", in: plan) == "Mon, Wed, Fri")
        #expect(value("Training days", in: makePlan(blocks: 1, daysPerBlock: 1)) == nil)
    }

    @Test("The facts read in one order, so the sheet never rearranges itself")
    func factsKeepTheirOrder() {
        let plan = makePlan(
            blocks: 2, daysPerBlock: 2, logged: 1, weekdays: [.monday], durationMinutes: 60)
        #expect(RoutineFacts.facts(of: plan).map(\.label)
            == ["Blocks", "Sessions", "Logged", "Training days", "Session length"])
    }
}
