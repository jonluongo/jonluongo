import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Whether the snapshot carries the whole block.
///
/// Claude reported reading four sessions of a nine-session block — Push in three
/// weeks, Pull missing entirely. That is the datastore lying to the trainer,
/// which is the one thing it may not do, so it is worth a test that fails loudly
/// rather than a reading of the code that concludes it looks fine.
///
/// If these pass, the exporter is not the fault and a truncated snapshot on disk
/// is a stale file: it is written by the phone, and a phone that has not opened
/// the app since the block changed has not rewritten it.
@Suite("Snapshot completeness")
struct SnapshotCompletenessTests {

    /// Three weeks of three training days, each with one exercise of three sets.
    private func block(in context: ModelContext) throws {
        let plan = TrainingPlan(
            title: "Push Pull Legs", goal: "Hypertrophy", generatedAt: Date(),
            catalogVersion: 5, sourceDocumentID: UUID())
        context.insert(plan)
        for ordinal in 1...3 {
            let week = TrainingWeek(ordinal: ordinal, label: "Week \(ordinal)")
            context.insert(week)
            week.plan = plan
            for (weekday, focus) in [
                (Weekday.monday, "Push"), (.wednesday, "Pull"), (.friday, "Legs"),
            ] {
                let day = WorkoutDay(weekday: weekday, focus: focus, durationMinutes: 60)
                context.insert(day)
                day.week = week
                let exercise = PlannedExercise(
                    exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                    displayName: "Barbell Bench Press", order: 0,
                    targetSets: 3, repRange: "6-8")
                context.insert(exercise)
                exercise.day = day
            }
        }
        try context.saveOrThrow()
    }

    @Test("Every week and every day of a block reaches the snapshot")
    func nothingIsDropped() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        try block(in: context)

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 4)
        let plan = try #require(snapshot.firstDocument)

        #expect(snapshot.routines.count == 1)
        #expect(plan.blocks.count == 3, "three weeks were prescribed")
        #expect(plan.blocks.allSatisfy { $0.days.count == 3 }, "three days in every block")
        #expect(plan.blocks.flatMap(\.days).count == 9, "nine sessions in all")
    }

    @Test("Every session keeps its name and its exercises")
    func daysKeepWhatTheyPrescribe() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        try block(in: context)

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 4)
        let days = try #require(snapshot.firstDocument).blocks.flatMap(\.days)

        // Not just the count: a day that crossed with no exercises would read as
        // a rest day to Claude, which is a different block from the one written.
        #expect(days.allSatisfy { $0.exercises.count == 1 })
        #expect(Set(days.map(\.focus)) == ["Push", "Pull", "Legs"])
        #expect(days.filter { $0.focus == "Pull" }.count == 3, "Pull is in all three weeks")
    }

    @Test("A week the record holds with no days still crosses as itself")
    func emptyWeekIsNotDropped() throws {
        // A week Claude wrote nothing into is a week he should see as empty,
        // not one the snapshot quietly omits — the second reads as a shorter
        // block than he prescribed.
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = TrainingPlan(
            title: "Sparse", generatedAt: Date(), catalogVersion: 5,
            sourceDocumentID: UUID())
        context.insert(plan)
        for ordinal in 1...2 {
            let week = TrainingWeek(ordinal: ordinal)
            context.insert(week)
            week.plan = plan
        }
        try context.saveOrThrow()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 4)
        #expect(try #require(snapshot.firstDocument).blocks.count == 2)
    }

    // MARK: - A routine grown a block at a time

    /// One block of one Monday push session, at `load`.
    private func routine(id: UUID, blocks: Int, load: Double) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Date(), title: "Autumn Strength",
            blocks: (1...blocks).map { ordinal in
                PlanDocumentBlock(label: "Block \(ordinal)", days: [
                    PlanDocumentDay(
                        weekday: .monday, focus: "Push",
                        exercises: [
                            PlanDocumentExercise(
                                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                                displayName: "Barbell Bench Press", sets: 3, repRange: "6-8",
                                suggestedLoad: Mass(
                                    value: ordinal == blocks ? load : 185, unit: .pounds))
                        ])
                ])
            })
    }

    /// Trains every session of the block he is on, whole.
    private func trainCurrentBlock(of plan: TrainingPlan, in context: ModelContext) throws {
        let ordinal = try #require(BlockSelection.currentBlockOrdinal(in: plan.orderedWeeks))
        let block = try #require(plan.orderedWeeks.first { $0.ordinal == ordinal })
        for day in block.orderedDays {
            SetSeeding.seedMissingSets(for: day.orderedExercises, in: context)
            for exercise in day.orderedExercises {
                for set in exercise.loggedSets ?? [] {
                    set.isCompleted = true
                    set.reps = 8
                }
            }
            day.completedAt = Date()
        }
        try context.saveOrThrow()
    }

    @Test("A second week trained on a grown routine exports beside the first, not over it")
    func aGrownRoutineExportsEveryBlocksWork() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let catalog = try ExerciseCatalog.bundled()
        let id = UUID()

        let plan = try PlanImporter.import(
            routine(id: id, blocks: 1, load: 185), into: context, catalog: catalog)
        try trainCurrentBlock(of: plan, in: context)
        try PlanImporter.import(
            routine(id: id, blocks: 2, load: 200), into: context, catalog: catalog)
        try trainCurrentBlock(of: plan, in: context)

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: catalog.version)
        let routine = try #require(snapshot.routines.first)

        // The steady state of the weekly loop, which the unit tests reach one
        // hop at a time: two blocks written a week apart, both trained, both in
        // the record under their own ordinal.
        #expect(snapshot.routines.count == 1, "one routine, not one per week")
        #expect(routine.document.blocks.count == 2)
        #expect(routine.sessions.count == 2)
        #expect(routine.sessions.allSatisfy { $0.completedAt != nil })
        #expect(Set(snapshot.log.map(\.blockOrdinal)) == [1, 2])
        #expect(snapshot.log.count == 6, "three sets a session, both sessions")

        // The load he trained the second week at is the second block's, so the
        // week's work is not filed under the week before it.
        let second = snapshot.log.filter { $0.blockOrdinal == 2 }
        #expect(second.allSatisfy { $0.load == Mass(value: 200, unit: .pounds) })
        #expect(second.count == 3)
    }
}
