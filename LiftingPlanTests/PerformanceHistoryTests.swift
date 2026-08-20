import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Which past session becomes the figure a lifter is shown when the plan named
/// no load.
///
/// **The wrong answer here is a number he trains against.** The ghost in an
/// empty weight field is whatever this returns, so picking the wrong session
/// puts a weight from three weeks ago — or from a set he never finished — under
/// his hands. Every rule that prevents it is a filter or a sort, and both fail
/// quietly: the field still fills, with the wrong figure.
///
/// The type is the single hierarchy walk for logged-exercise data and had no
/// suite of its own. Built through the real importer, over a live in-memory
/// store, because the traversal is the subject.
@Suite("What he did last time")
struct PerformanceHistoryTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// One imported block holding one bench exercise, with its working sets
    /// logged at `load` on `date`. `sets` rows are created and ticked.
    @discardableResult
    private func block(
        _ context: ModelContext, title: String, load: Double, on date: Date,
        displayName: String = "Bench", ticked: Bool = true
    ) throws -> PlannedExercise {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: title,
            days: [
                PlanDocumentDay(
                    weekday: .monday, focus: "Push",
                    exercises: [
                        PlanDocumentExercise(
                            exerciseID: Self.bench, displayName: displayName,
                            sets: 3, repRange: "5")
                    ])
            ])
        let plan = try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled())
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        let exercise = try #require(day.orderedExercises.first)

        SetSeeding.seedMissingSets(for: [exercise], in: context)
        for set in exercise.loggedSets ?? [] {
            set.isCompleted = ticked
            set.completedAt = date
            set.reps = 5
            set.load = Mass(value: load, unit: .pounds)
        }
        try context.save()
        return exercise
    }

    private func plans(in context: ModelContext) throws -> [TrainingPlan] {
        try context.fetch(FetchDescriptor<TrainingPlan>())
    }

    private func daysAgo(_ days: Int) -> Date {
        Self.instant.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    // MARK: - The most recent session, not the first one found

    @Test("The newest logged session is the one he is shown")
    func theNewestSessionWins() throws {
        let context = try context()
        try block(context, title: "Older", load: 185, on: daysAgo(21))
        try block(context, title: "Newer", load: 205, on: daysAgo(7))

        let history = try #require(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: nil, from: try plans(in: context)))

        #expect(history.recentSets.first?.load?.value == 205)
    }

    @Test("Order of arrival does not decide it — the dates do")
    func arrivalOrderIsNotTheAnswer() throws {
        // The same two blocks, imported the other way round. A traversal that
        // took the first match rather than the newest would flip its answer here
        // and nowhere else.
        let context = try context()
        try block(context, title: "Newer", load: 205, on: daysAgo(7))
        try block(context, title: "Older", load: 185, on: daysAgo(21))

        let history = try #require(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: nil, from: try plans(in: context)))

        #expect(history.recentSets.first?.load?.value == 205)
    }

    // MARK: - Today's own rows are not last time

    @Test("The session being logged is not offered as its own history")
    func todayDoesNotShadowItself() throws {
        let context = try context()
        try block(context, title: "Last week", load: 185, on: daysAgo(7))
        let today = try block(context, title: "Today", load: 225, on: Self.instant)

        let history = try #require(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: today, from: try plans(in: context)))

        // 225 is what he is doing now; the ghost must be what he did before it.
        #expect(history.recentSets.first?.load?.value == 185)
    }

    // MARK: - Only what he actually performed

    @Test("A session of rows he never ticked is not history")
    func untouchedRowsAreNotHistory() throws {
        let context = try context()
        try block(context, title: "Performed", load: 185, on: daysAgo(21))
        try block(context, title: "Opened, never logged", load: 225, on: daysAgo(1), ticked: false)

        let history = try #require(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: nil, from: try plans(in: context)))

        // The newer block is newer and holds nothing he did. Showing its 225
        // would put a figure under his hands that nobody performed.
        #expect(history.recentSets.first?.load?.value == 185)
    }

    @Test("Nothing logged anywhere answers nothing, rather than an empty session")
    func noHistoryAtAllIsNil() throws {
        let context = try context()
        try block(context, title: "Opened, never logged", load: 225, on: daysAgo(1), ticked: false)

        #expect(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: nil, from: try plans(in: context)) == nil)
    }

    // MARK: - Joined on identity, never on the name

    @Test("A movement renamed between blocks keeps one history")
    func historyJoinsOnTheIdentityNotTheName() throws {
        // Two plans naming the same catalog movement differently. Keyed on the
        // display name, a lift's record fragments and last time's figure
        // vanishes the week the coach writes the name another way.
        let context = try context()
        try block(context, title: "Older", load: 185, on: daysAgo(21), displayName: "Bench Press")
        try block(
            context, title: "Newer", load: 205, on: daysAgo(7),
            displayName: "Barbell Bench Press")

        let history = try #require(
            PerformanceHistory.latestHistory(
                for: Self.bench, excluding: nil, from: try plans(in: context)))

        #expect(history.exerciseID == Self.bench)
        #expect(history.recentSets.first?.load?.value == 205)
    }
}
