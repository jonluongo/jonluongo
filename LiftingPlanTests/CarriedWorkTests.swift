import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Work carried over a distance, from the plan Claude wrote to the snapshot he
/// reads back.
///
/// The gap these close is the one the last pass named and left open: a farmer's
/// carry prescribed as "40 metres" reached the lifter correctly, was displayed
/// correctly, and there was nowhere to record how far he actually went. Each
/// test below stands at one point on the path a distance now takes — and at each
/// of them, metres are neither repetitions nor seconds.
@Suite("Carried work through the app")
struct CarriedWorkTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let carry = ExerciseID(rawValue: "kettlebell-farmers-carry")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    /// A block of one carried movement, imported the way a real plan arrives.
    private func imported(
        _ target: String, sets: Int = 3, into context: ModelContext
    ) throws -> PlannedExercise {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Carries",
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Carries",
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.carry, displayName: "Kettlebell Farmers Carry",
                    sets: sets, repRange: target, restSeconds: 90)])]
        )
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        return try #require(day.orderedExercises.first)
    }

    // MARK: - The catalog really does hold carried work

    @Test("The exercise this is all about is in the catalog")
    func carryExists() throws {
        #expect(try catalog().exercise(id: Self.carry) != nil)
    }

    // MARK: - The prescription reaches the lifter as a carry

    @Test("A prescription written in metres is read as a carry, not as reps or a hold")
    func carriedPrescriptionIsRecognized() throws {
        let exercise = try imported("40 metres", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .distance(.metres))
        #expect(RepPrescription.seededReps(for: exercise.repRange) == nil)
        #expect(HoldPrescription.seededSeconds(for: exercise.repRange) == nil)
        #expect(
            WorkPrescription.seededDistance(for: exercise.repRange)
                == Distance(value: 40, unit: .metres))
        #expect(RepPrescription.targetText(for: exercise.repRange) == "40 metres")
    }

    @Test("A counted prescription is not a carry")
    func countedPrescriptionIsNotCarried() throws {
        let exercise = try imported("8-12", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .repetitions)
        #expect(WorkPrescription.seededDistance(for: exercise.repRange) == nil)
    }

    @Test("A held prescription is not a carry either")
    func heldPrescriptionIsNotCarried() throws {
        let exercise = try imported("30 seconds", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .time)
        #expect(WorkPrescription.seededDistance(for: exercise.repRange) == nil)
    }

    @Test("A range of distances seeds nothing and is still a carry")
    func rangeSeedsNothing() throws {
        let exercise = try imported("50-100 yd", into: try context())

        #expect(WorkPrescription.measure(of: exercise) == .distance(.yards))
        #expect(WorkPrescription.seededDistance(for: exercise.repRange) == nil)
    }

    @Test("An exercise whose sets each state a distance is a carry as a whole")
    func perSetDistancesMakeTheExerciseACarry() throws {
        let context = try context()
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(
                weekday: .monday,
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.carry, displayName: "Kettlebell Farmers Carry",
                    sets: [
                        SetPrescription(repRange: "40 m"),
                        SetPrescription(repRange: "30 m"),
                    ])])]
        )
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        let exercise = try #require(
            plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)

        #expect(WorkPrescription.measure(of: exercise) == .distance(.metres))
        #expect(
            exercise.prescribedSets.map { WorkPrescription.seededDistance(for: $0.repRange) }
                == [Distance(value: 40, unit: .metres), Distance(value: 30, unit: .metres)])
    }

    // MARK: - What a logged carry becomes

    /// One carry logged against a prescription, exported.
    private func exported(
        target: String, distance: Distance?, reps: Int = 0, durationSeconds: Int? = nil
    ) throws -> SnapshotLoggedSet {
        let context = try context()
        let exercise = try imported(target, sets: 1, into: context)
        let set = LoggedSet(
            setIndex: 0, reps: reps, durationSeconds: durationSeconds,
            distance: distance, isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        return try #require(
            snapshot.plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)
    }

    @Test("A carried set records its distance and no repetitions and no seconds")
    func carriedSetRecordsDistance() throws {
        let reported = try exported(
            target: "40 metres", distance: Distance(value: 38, unit: .metres))

        #expect(reported.distance == Distance(value: 38, unit: .metres))
        #expect(reported.reps == 0, "thirty-eight metres is not thirty-eight repetitions")
        #expect(reported.durationSeconds == nil, "nor is it thirty-eight seconds")
    }

    @Test("A carry logged in yards stays in yards")
    func unitIsNotConverted() throws {
        let reported = try exported(
            target: "50 yd", distance: Distance(value: 50, unit: .yards))

        #expect(reported.distance?.unit == .yards)
        #expect(reported.distance?.value == 50)
    }

    @Test("A counted set reports no distance rather than a zero one")
    func countedSetReportsNoDistance() throws {
        let reported = try exported(target: "5", distance: nil, reps: 5)

        #expect(reported.reps == 5)
        #expect(reported.distance == nil)
    }

    @Test("A held set reports no distance either")
    func heldSetReportsNoDistance() throws {
        let reported = try exported(
            target: "30 seconds", distance: nil, durationSeconds: 34)

        #expect(reported.durationSeconds == 34)
        #expect(reported.distance == nil)
    }

    @Test("A carry survives the snapshot's own encoding")
    func carriedSetSurvivesEncoding() throws {
        let context = try context()
        let exercise = try imported("40 metres", sets: 1, into: context)
        let set = LoggedSet(
            setIndex: 0, distance: Distance(value: 38, unit: .metres), isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)
        let reported = try #require(
            decoded.plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)

        #expect(reported.distance == Distance(value: 38, unit: .metres))
        #expect(String(decoding: data, as: UTF8.self).contains("\"distance\""))
        #expect(String(decoding: data, as: UTF8.self).contains("\"unit\" : \"m\""))
    }

    // MARK: - What the lifter is shown last time

    @Test("Last session's carry is reported as a distance, not as a rep count")
    func previousCarryReadsAsDistance() throws {
        let context = try context()
        let exercise = try imported("40 metres", sets: 1, into: context)
        let set = LoggedSet(
            setIndex: 0, distance: Distance(value: 38, unit: .metres), isCompleted: true)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        let history = PerformanceHistory.history(from: exercise)

        #expect(history.recentSets.first?.distance == Distance(value: 38, unit: .metres))
        #expect(history.recentSets.first?.reps == 0)
        #expect(history.recentSets.first?.durationSeconds == nil)
    }

    // MARK: - Absence stays absence

    @Test("A set nobody carried has no distance at all, not a distance of zero")
    func absenceIsNotZero() throws {
        let context = try context()
        let set = LoggedSet(setIndex: 0, reps: 5)
        context.insert(set)
        try context.save()

        #expect(set.distance == nil)
    }
}
