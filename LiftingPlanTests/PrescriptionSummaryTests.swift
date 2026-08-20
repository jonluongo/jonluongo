import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The line above a set table, and the line under one row of it.
///
/// **What makes this worth testing is what it refuses to say.** Both lines exist
/// only to state what the table will not: the count and the target are already
/// in every row's own fields, and repeating them is the screen saying the same
/// thing twice. Every rule here is a rule about staying quiet, which is the kind
/// that rots silently — a line that starts appearing where it should not looks
/// like a feature, and a line that stops appearing where it should takes the
/// effort off the logging screen altogether with nothing to show for it.
///
/// The type had no tests. It is built through the real importer rather than by
/// hand, because `prescribedSets` is derived and a fixture would prove only that
/// a fixture behaves.
@Suite("What the prescription lines say")
struct PrescriptionSummaryTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func imported(_ exercise: PlanDocumentExercise) throws -> PlannedExercise {
        let context = ModelContext(try StoreContainer.inMemory())
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Block",
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", exercises: [exercise])])
        let plan = try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled())
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        return try #require(day.orderedExercises.first)
    }

    private func kg(_ value: Double) -> Mass { Mass(value: value, unit: .kilograms) }
    private func rpe(_ value: String) -> IntensityTarget {
        IntensityTarget(scale: .rpe, value: value)
    }

    // MARK: - The header states the one thing no row will

    @Test("An effort every set shares is stated once, above the table")
    func oneSharedEffortIsStatedOnce() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                repRange: "8-12", intensity: rpe("8")))

        #expect(PrescriptionSummary.aboveTable(for: exercise) == "80% effort")
    }

    @Test("The count and the target are never restated above the rows that carry them")
    func theHeaderDoesNotRepeatTheTable() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                repRange: "8-12", suggestedLoad: kg(100), intensity: rpe("8")))

        let line = try #require(PrescriptionSummary.aboveTable(for: exercise))
        #expect(!line.contains("3"), "the rows are numbered")
        #expect(!line.contains("8-12"), "every rep field already reads it")
        #expect(!line.contains("100"), "every load field already reads it")
    }

    @Test("Nothing prescribed above the table draws no line at all")
    func nothingToSayDrawsNothing() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12"))

        #expect(PrescriptionSummary.aboveTable(for: exercise) == nil)
    }

    @Test("Sets asking for different efforts leave the header silent")
    func differingEffortsAreNotSummarisedAbove() throws {
        // A span above the table would say what the sets cover between them and
        // not what any one of them asks for, so each row states its own instead.
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(intensity: rpe("7")),
                    SetPrescription(intensity: rpe("8")),
                    SetPrescription(intensity: rpe("9")),
                ],
                repRange: "5"))

        #expect(PrescriptionSummary.aboveTable(for: exercise) == nil)
    }

    // MARK: - The row states what the header has not

    @Test("A set with its own effort states it, once the header has gone quiet")
    func aSetWithItsOwnEffortStatesIt() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(intensity: rpe("7")),
                    SetPrescription(intensity: rpe("9")),
                ],
                repRange: "5"))
        let sets = exercise.prescribedSets

        #expect(PrescriptionSummary.detail(for: sets.first, in: exercise) == "70% effort")
        #expect(PrescriptionSummary.detail(for: sets.last, in: exercise) == "90% effort")
    }

    @Test("A set carrying a prescribed load is not also shown an effort")
    func aLoadedSetIsNotShownItsWorking() throws {
        // The intensity is already baked into the number on the bar; printing
        // both under every row is showing the coach's working.
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(suggestedLoad: kg(90), intensity: rpe("7")),
                    SetPrescription(suggestedLoad: kg(100), intensity: rpe("9")),
                ],
                repRange: "5"))

        #expect(PrescriptionSummary.detail(for: exercise.prescribedSets.first, in: exercise) == nil)
    }

    @Test("A note written about one set in particular reaches that row")
    func aSetNoteReachesItsRow() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(),
                    SetPrescription(repRange: "AMRAP", notes: "Take it to failure"),
                ],
                repRange: "5", suggestedLoad: kg(100)))

        #expect(
            PrescriptionSummary.detail(for: exercise.prescribedSets.last, in: exercise)
                == "Take it to failure")
    }

    @Test("An effort and a note about the same set are joined, not one dropped")
    func effortAndNoteAreBothStated() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(intensity: rpe("7")),
                    SetPrescription(intensity: rpe("9"), notes: "Last one"),
                ],
                repRange: "5"))

        #expect(
            PrescriptionSummary.detail(for: exercise.prescribedSets.last, in: exercise)
                == "90% effort · Last one")
    }

    @Test("A row the plan never described asks nothing of him")
    func anUnprescribedRowSaysNothing() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                repRange: "8-12", intensity: rpe("8")))

        // A warm-up, or a set he added past the ones prescribed.
        #expect(PrescriptionSummary.detail(for: nil, in: exercise) == nil)
    }

    @Test("A shared effort is stated above the table and not again on every row")
    func theSharedEffortIsNotSaidTwice() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                repRange: "8-12", intensity: rpe("8")))

        #expect(PrescriptionSummary.aboveTable(for: exercise) != nil)
        #expect(
            exercise.prescribedSets
                .allSatisfy { PrescriptionSummary.detail(for: $0, in: exercise) == nil })
    }
}
