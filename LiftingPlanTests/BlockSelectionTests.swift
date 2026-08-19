import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Every week Claude prescribed has to be reachable, and the header has to stop
/// claiming a finished week once it is finished.
///
/// The plan screen used to read `plan.orderedWeeks.first` in both places under
/// a heading of "This Week": a four-week block lost weeks 2–4 entirely,
/// including its deload, and `completedAt` on week 1 pinned the header at
/// "3 of 3 sessions done" for the rest of the block.
@Suite("Plan week selection")
struct PlanWeekSelectionTests {

    @Test("A block opens on week 1 while week 1 is unfinished")
    func opensOnFirstUnfinishedWeek() {
        let weeks = [
            week(1, days: [day(.monday, done: true), day(.wednesday, done: false)]),
            week(2, days: [day(.monday, done: false)]),
        ]
        #expect(BlockSelection.currentWeekOrdinal(in: weeks) == 1)
    }

    @Test("Finishing week 1 moves the screen on to week 2")
    func movesOnWhenAWeekIsFinished() {
        // This is the bug the header told: week 1 complete, and the screen
        // stayed on it reporting "3 of 3 sessions done" forever.
        let weeks = [
            week(1, days: [day(.monday, done: true), day(.wednesday, done: true)]),
            week(2, days: [day(.monday, done: false)]),
            week(3, days: [day(.monday, done: false)]),
        ]
        #expect(BlockSelection.currentWeekOrdinal(in: weeks) == 2)
    }

    @Test("A finished block stays on its last week rather than falling back to the first")
    func finishedBlockStaysOnTheLastWeek() {
        let weeks = [
            week(1, days: [day(.monday, done: true)]),
            week(2, days: [day(.monday, done: true)]),
        ]
        #expect(BlockSelection.currentWeekOrdinal(in: weeks) == 2)
    }

    @Test("Weeks out of storage order are read in program order")
    func ordinalsDecideOrderNotStorage() {
        // SwiftData does not guarantee relationship ordering, so the deload
        // week can come back first.
        let weeks = [
            week(3, days: [day(.monday, done: false)]),
            week(1, days: [day(.monday, done: true)]),
            week(2, days: [day(.monday, done: false)]),
        ]
        #expect(BlockSelection.currentWeekOrdinal(in: weeks) == 2)
    }

    @Test("A week whose sessions have not arrived is not a finished week")
    func emptyWeekIsNotFinished() {
        let empty = week(2, days: [])
        #expect(BlockSelection.isFinished(empty) == false)
        let weeks = [week(1, days: [day(.monday, done: true)]), empty]
        #expect(BlockSelection.currentWeekOrdinal(in: weeks) == 2)
    }

    @Test("A plan with no weeks selects nothing")
    func noWeeks() {
        #expect(BlockSelection.currentWeekOrdinal(in: []) == nil)
    }

    @Test("A week is titled by its position and whatever the plan called it")
    func weekTitles() {
        #expect(BlockSelection.title(for: week(2, days: [])) == "Block 2")
        #expect(BlockSelection.title(for: week(2, days: [], label: "Accumulation"))
            == "Block 2 · Accumulation")
        // A deload the plan did not label is still said, not lost.
        #expect(BlockSelection.title(for: week(4, days: [], isDeload: true))
            == "Block 4 · Deload")
        #expect(BlockSelection.title(for: week(4, days: [], label: "Taper", isDeload: true))
            == "Block 4 · Taper")
    }

    @Test("Every week of a stored block is reachable, deload included")
    func everyStoredWeekIsReachable() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = TrainingPlan(title: "Four-week block", weekCount: 4)
        plan.weeks = [
            week(1, days: [day(.monday, done: true)], label: "Accumulation"),
            week(2, days: [day(.monday, done: false)], label: "Accumulation"),
            week(3, days: [day(.monday, done: false)], label: "Intensification"),
            week(4, days: [day(.monday, done: false)], label: "Deload", isDeload: true),
        ]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.orderedWeeks.map(\.ordinal) == [1, 2, 3, 4])
        #expect(loaded.orderedWeeks.map(BlockSelection.title(for:)).last == "Block 4 · Deload")
        #expect(BlockSelection.currentWeekOrdinal(in: loaded.orderedWeeks) == 2)
    }

    // MARK: - Fixtures

    private func week(
        _ ordinal: Int, days: [WorkoutDay], label: String = "", isDeload: Bool = false
    ) -> TrainingWeek {
        let week = TrainingWeek(ordinal: ordinal, label: label, isDeload: isDeload)
        week.days = days
        return week
    }

    private func day(_ weekday: Weekday, done: Bool) -> WorkoutDay {
        WorkoutDay(weekday: weekday, focus: "Full Body", completedAt: done ? Date() : nil)
    }
}
