import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// That a plan imported and read back is the plan that arrived.
///
/// **This is the property the snapshot rewrite stands on.** Today a
/// prescription exists in three vocabularies — the document Claude writes, the
/// `@Model`s that store it, and a third set of `Snapshot*` types that report it
/// back — and the first and third disagree in shape: a document nests a group,
/// the snapshot flattens it into a marker on each member. The third goes away by
/// having the snapshot carry the document itself, which is only honest if the
/// store holds everything the document said. Every case here is a field that
/// would otherwise be lost quietly, and the last one is the whole document at
/// once.
@Suite("Plan document round trip")
@MainActor
struct PlanDocumentRoundTripTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let row = ExerciseID(rawValue: "barbell-bent-over-row")
    private static let curl = ExerciseID(rawValue: "dumbbell-curl")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog { try ExerciseCatalog.bundled() }

    /// Imports a document and reads it straight back out.
    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument? {
        let context = try context()
        let plan = try PlanImporter.import(document, into: context, catalog: try catalog())
        return PlanDocument(reconstructing: plan)
    }

    // MARK: - The ordinary block

    @Test("A block of plain exercises comes back as it was written")
    func plainBlockRoundTrips() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            title: "Autumn strength", goal: "Add 20 lb to the squat",
            durationMinutes: 60, notes: "The fourth week is lighter on purpose.",
            weeks: [
                PlanDocumentWeek(label: "Accumulation", isDeload: false, days: [
                    PlanDocumentDay(
                        weekday: .monday, focus: "Push", durationMinutes: 55,
                        icon: .strength,
                        exercises: [
                            PlanDocumentExercise(
                                exerciseID: Self.bench, displayName: "Barbell Bench Press",
                                sets: 3, repRange: "8-12", restSeconds: 180,
                                suggestedLoad: Mass(value: 185, unit: .pounds),
                                intensity: IntensityTarget(scale: .rpe, value: "8"),
                                tempo: "3-0-1-0", notes: "Pause the last rep")
                        ]),
                ]),
                PlanDocumentWeek(label: "Deload", isDeload: true, days: [
                    PlanDocumentDay(weekday: .friday, focus: "Pull", exercises: [
                        PlanDocumentExercise(
                            exerciseID: Self.row, displayName: "Barbell Row", sets: 2)
                    ]),
                ]),
            ])

        #expect(try roundTrip(document) == document)
    }

    @Test("A week the plan did not name comes back unnamed, not called nothing")
    func unnamedWeekStaysUnnamed() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            weeks: [PlanDocumentWeek(days: [
                PlanDocumentDay(weekday: .monday, exercises: [
                    PlanDocumentExercise(
                        exerciseID: Self.bench, displayName: "Barbell Bench Press", sets: 3)
                ])
            ])])

        let read = try #require(try roundTrip(document))
        #expect(read.weeks[0].label == nil)
        #expect(read == document)
    }

    // MARK: - The things that would be lost quietly

    @Test("Sets the plan listed one at a time come back listed, not collapsed")
    func statedSetsSurvive() throws {
        // A ramp. Collapsed into a count and one prescription it would read as
        // three sets of the lightest, which is a session nobody wrote.
        let ramp = [
            SetPrescription(repRange: "5", suggestedLoad: Mass(value: 135, unit: .pounds)),
            SetPrescription(repRange: "3", suggestedLoad: Mass(value: 185, unit: .pounds)),
            SetPrescription(
                repRange: "1", suggestedLoad: Mass(value: 225, unit: .pounds),
                notes: "Last set to failure"),
        ]
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, exercises: [
                PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: ramp, restSeconds: 240)
            ])])

        let read = try #require(try roundTrip(document))
        #expect(read == document)
        #expect(read.weeks[0].days[0].entries[0].exercises[0].statedSets == ramp)
    }

    @Test("A superset comes back as a group, with the rest on the group")
    func groupRoundTrips() throws {
        // The store puts a group's rest on the member the round ends with; the
        // format refuses a rest inside a group at all. Round-tripping is what
        // proves the two say the same thing.
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, focus: "Upper", entries: [
                .exercise(PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: 3, restSeconds: 180)),
                .group(PlanDocumentGroup(
                    exercises: [
                        PlanDocumentExercise(
                            exerciseID: Self.row, displayName: "Barbell Row", sets: 3),
                        PlanDocumentExercise(
                            exerciseID: Self.curl, displayName: "Dumbbell Curl", sets: 3),
                    ],
                    restSeconds: 90)),
            ])])

        let read = try #require(try roundTrip(document))
        #expect(read == document)
        guard case .group(let group) = read.weeks[0].days[0].entries[1] else {
            Issue.record("Expected the second entry to be a group")
            return
        }
        #expect(group.restSeconds == 90)
        #expect(group.exercises.allSatisfy { $0.restSeconds == nil })
    }

    @Test("A session's mark comes back, and a day he marked nothing carries nothing")
    func iconsSurvive() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [
                PlanDocumentDay(weekday: .monday, icon: .intervals, exercises: [
                    PlanDocumentExercise(
                        exerciseID: Self.bench, displayName: "Barbell Bench Press", sets: 1)
                ]),
                PlanDocumentDay(weekday: .wednesday, exercises: [
                    PlanDocumentExercise(
                        exerciseID: Self.row, displayName: "Barbell Row", sets: 1)
                ]),
            ])

        let read = try #require(try roundTrip(document))
        #expect(read.weeks[0].days[0].icon == .intervals)
        #expect(read.weeks[0].days[1].icon == nil)
        #expect(read == document)
    }

    @Test("A rest day comes back as a day with no work, not as a day that vanished")
    func restDaySurvives() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [
                PlanDocumentDay(weekday: .monday, exercises: [
                    PlanDocumentExercise(
                        exerciseID: Self.bench, displayName: "Barbell Bench Press", sets: 3)
                ]),
                PlanDocumentDay(weekday: .tuesday, focus: "Rest", exercises: []),
            ])

        let read = try #require(try roundTrip(document))
        #expect(read.weeks[0].days.count == 2)
        #expect(read == document)
    }

    // MARK: - What cannot be reconstructed

    @Test("A block that never came from a document reconstructs to nothing")
    func aPlanWithNoDocumentIsNotOne() throws {
        // Nothing in the app can make one — `PlanImporter` is the only producer
        // and it writes all three — so this is answered with an absence rather
        // than with an identity nobody wrote.
        let context = try context()
        let plan = TrainingPlan(title: "Hand-made")
        context.insert(plan)

        #expect(PlanDocument(reconstructing: plan) == nil)
    }
}
