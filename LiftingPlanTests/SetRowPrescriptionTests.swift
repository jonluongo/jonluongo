import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What one row of a set table is shown beside the two numbers the lifter types.
///
/// **Per set, not per exercise.** That is the whole of this type: a ramp shows
/// the load of the set being logged rather than one figure standing in for all
/// of them, and a row past the ones prescribed shows nothing, because a fourth
/// row under a three-set prescription is the lifter's own and not the plan's.
/// Both rules are off-by-one arithmetic over a derived array, which is the kind
/// that breaks quietly and shows a lifter the wrong set's weight.
///
/// It had no tests. Built through the real importer, because `prescribedSets` is
/// derived and a fixture would prove only that a fixture behaves.
@Suite("What one row is shown")
struct SetRowPrescriptionTests {

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

    private func reading(
        _ exercise: PlannedExercise, unit: MassUnit = .kilograms
    ) -> SetRowPrescription {
        SetRowPrescription(exercise: exercise, plans: [], unit: unit)
    }

    /// A ramp: three sets, each heavier than the last.
    private func ramp() throws -> PlannedExercise {
        try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench",
                sets: [
                    SetPrescription(suggestedLoad: kg(60)),
                    SetPrescription(suggestedLoad: kg(70)),
                    SetPrescription(suggestedLoad: kg(80)),
                ],
                repRange: "5"))
    }

    // MARK: - The set being logged, not one standing in for the rest

    @Test("Each working set is shown the load prescribed for that set")
    func eachSetIsShownItsOwnLoad() throws {
        let reading = reading(try ramp())

        #expect(reading.loadTarget(reading.prescription(forWorkingNumber: 1, isWarmup: false))
            == "60")
        #expect(reading.loadTarget(reading.prescription(forWorkingNumber: 2, isWarmup: false))
            == "70")
        #expect(reading.loadTarget(reading.prescription(forWorkingNumber: 3, isWarmup: false))
            == "80")
    }

    @Test("A set past the ones prescribed is the lifter's own and is shown nothing")
    func anExtraSetIsNotStretchedToFit() throws {
        let reading = reading(try ramp())
        let fourth = reading.prescription(forWorkingNumber: 4, isWarmup: false)

        #expect(fourth == nil, "nothing is stretched to cover it")
        #expect(reading.loadTarget(fourth) == "", "and an empty field, not the last set's 80")
    }

    @Test("A warm-up asks the plan nothing, whatever its number")
    func aWarmupIsNotAPrescribedSet() throws {
        let reading = reading(try ramp())

        #expect(reading.prescription(forWorkingNumber: 1, isWarmup: true) == nil)
        #expect(reading.prescription(forWorkingNumber: 2, isWarmup: true) == nil)
    }

    @Test("The numbering is the working set's, counted from one")
    func workingNumbersAreOneBased() throws {
        let exercise = try ramp()
        let reading = reading(exercise)

        // The off-by-one this arithmetic invites: set one is the first
        // prescription, not the second, and there is no set zero.
        #expect(
            reading.prescription(forWorkingNumber: 1, isWarmup: false)
                == exercise.prescribedSets.first)
        #expect(reading.prescription(forWorkingNumber: 0, isWarmup: false) == nil)
    }

    // MARK: - The unit is the lifter's, the figure is the plan's

    @Test("A load prescribed in kilos is shown in the unit he reads")
    func aPrescribedLoadIsConvertedForDisplay() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 1,
                repRange: "5", suggestedLoad: kg(100)))
        let inPounds = SetRowPrescription(exercise: exercise, plans: [], unit: .pounds)
        let first = inPounds.prescription(forWorkingNumber: 1, isWarmup: false)

        // 220.46 lb, shown to the one decimal a lifter reads off a plate
        // stack. The conversion is display only — the plan still states kilos,
        // and `Mass` keeps the unit it was written in.
        #expect(inPounds.loadTarget(first) == "220.5")
        #expect(first?.suggestedLoad?.unit == .kilograms, "the prescription is untouched")
        #expect(first?.suggestedLoad?.value == 100, "and its figure")
    }

    @Test("No load prescribed shows an empty field rather than a dash or a zero")
    func noLoadShowsNothing() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12"))
        let reading = reading(exercise)

        #expect(reading.loadTarget(reading.prescription(forWorkingNumber: 1, isWarmup: false))
            == "")
    }

    // MARK: - What the row measures

    @Test("What the row measures comes from the prescription and nothing else")
    func theMeasureIsThePrescriptions() throws {
        let counted = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12"))
        #expect(reading(counted).measure == .repetitions)

        let held = try imported(
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "front-plank"), displayName: "Plank",
                sets: 3, repRange: "45 seconds"))
        #expect(reading(held).measure == .time)

        let carried = try imported(
            PlanDocumentExercise(
                exerciseID: ExerciseID(rawValue: "kettlebell-farmers-carry"),
                displayName: "Carry", sets: 3, repRange: "40 metres"))
        #expect(reading(carried).measure == .distance(.metres))
    }

    // MARK: - Last time's figure, only where the plan named none

    @Test("With no history and no prescription, the field stays empty")
    func noHistoryShowsNothing() throws {
        let exercise = try imported(
            PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "8-12"))

        #expect(reading(exercise).previousLoad(workingIndex: 0, isWarmup: false) == "")
    }

    @Test("A warm-up is shown no ghost of last time either")
    func aWarmupHasNoGhost() throws {
        let exercise = try ramp()

        #expect(reading(exercise).previousLoad(workingIndex: 0, isWarmup: true) == "")
    }
}
