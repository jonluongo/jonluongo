import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Work held for time, from the plan Claude wrote to the snapshot he reads
/// back.
///
/// The bug these guard is the one the review found: a plank prescribed as
/// "30 seconds" reached the lifter correctly, and the field he typed 34 into
/// was a rep count. Thirty-four repetitions of a plank were then logged,
/// reported, and totalled as reps forever. Each test below stands at one point
/// on that path.
@Suite("Timed work through the app")
struct TimedWorkTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let plank = ExerciseID(rawValue: "front-plank")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    /// A block of one held movement, imported the way a real plan arrives.
    private func imported(
        _ target: String, sets: Int = 3, into context: ModelContext
    ) throws -> PlannedExercise {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Trunk",
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Trunk",
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.plank, displayName: "Plank",
                    sets: sets, repRange: target, restSeconds: 60)])]
        )
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        return try #require(day.orderedExercises.first)
    }

    // MARK: - The catalog really does hold timed work

    @Test("The exercise this is all about is in the catalog")
    func plankExists() throws {
        #expect(try catalog().exercise(id: Self.plank) != nil)
    }

    // MARK: - The prescription reaches the lifter as a hold

    @Test("A prescription written in seconds is read as a hold, not as reps")
    func timedPrescriptionIsRecognized() throws {
        let exercise = try imported("30 seconds", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .time)
        #expect(RepPrescription.seededReps(for: exercise.repRange) == nil)
        #expect(HoldPrescription.seededSeconds(for: exercise.repRange) == 30)
        #expect(RepPrescription.targetText(for: exercise.repRange) == "30 seconds")
    }

    @Test("A counted prescription is not a hold")
    func countedPrescriptionIsNotTimed() throws {
        let exercise = try imported("8-12", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .repetitions)
        #expect(HoldPrescription.seededSeconds(for: exercise.repRange) == nil)
    }

    @Test("An exercise whose sets each state a hold is timed as a whole")
    func perSetHoldsMakeTheExerciseTimed() throws {
        let context = try context()
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(
                weekday: .monday,
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.plank, displayName: "Plank",
                    sets: [
                        SetPrescription(repRange: "30 seconds"),
                        SetPrescription(repRange: "45 seconds"),
                    ])])]
        )
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        let exercise = try #require(
            plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)

        #expect(WorkPrescription.measure(of: exercise) == .time)
        #expect(
            exercise.prescribedSets.map { HoldPrescription.seededSeconds(for: $0.repRange) }
                == [30, 45])
    }

    // MARK: - What a logged hold becomes

    @Test("A held set records its seconds and no repetitions at all")
    func heldSetRecordsSeconds() throws {
        let context = try context()
        let exercise = try imported("30 seconds", sets: 1, into: context)
        let set = LoggedSet(setIndex: 0, durationSeconds: 34, isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let reported = try #require(
            snapshot.plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)

        #expect(reported.durationSeconds == 34)
        #expect(reported.reps == 0, "thirty-four seconds is not thirty-four repetitions")
    }

    @Test("A counted set reports no duration rather than a zero one")
    func countedSetReportsNoDuration() throws {
        let context = try context()
        let exercise = try imported("5", sets: 1, into: context)
        let set = LoggedSet(setIndex: 0, reps: 5, isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let reported = try #require(
            snapshot.plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)

        #expect(reported.reps == 5)
        #expect(reported.durationSeconds == nil)
    }

    @Test("A hold survives the snapshot's own encoding")
    func heldSetSurvivesEncoding() throws {
        let context = try context()
        let exercise = try imported("30 seconds", sets: 1, into: context)
        let set = LoggedSet(setIndex: 0, durationSeconds: 34, isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)
        let reported = try #require(
            decoded.plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)

        #expect(reported.durationSeconds == 34)
        #expect(String(decoding: data, as: UTF8.self).contains("\"durationSeconds\" : 34"))
    }

    // MARK: - What the lifter is shown last time

    @Test("Last session's hold is reported in seconds, not as a rep count")
    func previousHoldReadsAsSeconds() throws {
        let context = try context()
        let exercise = try imported("30 seconds", sets: 1, into: context)
        let set = LoggedSet(setIndex: 0, durationSeconds: 34, isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let history = PerformanceHistory.history(from: exercise)

        #expect(history.recentSets.first?.durationSeconds == 34)
        #expect(history.recentSets.first?.reps == 0)
    }
}
