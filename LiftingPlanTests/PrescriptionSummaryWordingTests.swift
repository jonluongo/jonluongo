import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The one line an exercise reads as on a screen the lifter is browsing.
///
/// Every prescribed exercise draws a name and one line, whatever kind of
/// prescription it is — that is the whole point of the wording, and it is a pure
/// string function over a prescription, so it is pinned here rather than
/// eyeballed. What each case must never do is claim something untrue: a span
/// states how far the sets reach between them, and nothing rounds, averages, or
/// picks one set out to stand for the others.
@Suite("The one line a prescription reads as")
struct PrescriptionSummaryWordingTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let squat = ExerciseID(rawValue: "barbell-squat")
    private static let plank = ExerciseID(rawValue: "front-plank")
    private static let carry = ExerciseID(rawValue: "kettlebell-farmers-carry")

    private func kg(_ value: Double) -> Mass { Mass(value: value, unit: .kilograms) }

    /// One imported exercise, taken the whole way through the document reader
    /// and the store so the line is read off exactly what the app would hold.
    private func imported(
        _ exercise: PlanDocumentExercise, unit: MassUnit = .kilograms
    ) throws -> String {
        try line(for: PlanDocumentDay(weekday: .monday, exercises: [exercise]), unit: unit)
    }

    /// The line of the first exercise of `day`, which for a group is the line of
    /// its first movement — a movement inside a superset is written by the same
    /// function as one performed on its own.
    private func line(for day: PlanDocumentDay, unit: MassUnit = .kilograms) throws -> String {
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = try PlanImporter.import(
            PlanDocument(
                id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Block",
                days: [day]),
            into: context, catalog: try ExerciseCatalog.bundled()
        )
        let stored = try #require(
            plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)
        return PrescriptionSummary.text(for: stored, unit: unit)
    }

    // MARK: - Sets that are all alike

    @Test("A uniform prescription states its count, its reps and its effort")
    func uniformStatesWhatEverySetAsks() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench", sets: 4, repRange: "8-10",
            suggestedLoad: kg(80))) == "4 × 8-10")

        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench", sets: 4, repRange: "8-10",
            intensity: IntensityTarget(scale: .rpe, value: "8"))) == "4 × 8-10 · RPE 8")

        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench", sets: 1, repRange: "5")) == "1 × 5")
    }

    /// A load every set shares is not on this line: the sets do not differ in
    /// it, so it says nothing about the shape of the work, and it reaches the
    /// lifter where he needs it — in the weight field of the row he is lifting.
    @Test("A load stated once for every set is left to the row that lifts it")
    func sharedLoadIsNotOnTheBrowsingLine() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench", sets: 3, repRange: "5",
            suggestedLoad: kg(100))) == "3 × 5")
    }

    // MARK: - Sets that differ

    @Test("A ramp states the span of load it climbs, in one line")
    func rampSpansItsLoad() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.squat, displayName: "Squat",
            sets: [
                SetPrescription(suggestedLoad: kg(60)),
                SetPrescription(suggestedLoad: kg(70)),
                SetPrescription(suggestedLoad: kg(80)),
            ],
            repRange: "5")) == "3 × 5 · 60-80 kg")
    }

    /// The efforts differ, so the span says so. It is not the top set's figure
    /// standing for all three, and the top set's own row still states its own.
    @Test("A ramp whose sets each state an effort spans the efforts too")
    func rampSpansItsEffort() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.squat, displayName: "Squat",
            sets: [
                SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "7")),
                SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "8")),
                SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "9")),
            ],
            repRange: "5")) == "3 × 5 · RPE 7-9")
    }

    /// An effort asked of one set alone is not an effort asked of the exercise.
    /// Writing "RPE 9" here would claim all three sets were prescribed it, so
    /// nothing is written and the set's own row carries it instead.
    @Test("An effort only the top set states is not claimed for the exercise")
    func partialEffortIsNotClaimedForEverySet() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.squat, displayName: "Squat",
            sets: [
                SetPrescription(suggestedLoad: kg(60)),
                SetPrescription(suggestedLoad: kg(70)),
                SetPrescription(
                    suggestedLoad: kg(80),
                    intensity: IntensityTarget(scale: .rpe, value: "9")),
            ],
            repRange: "5")) == "3 × 5 · 60-80 kg")
    }

    /// Two scales are two sentences and no range covers both, so neither is
    /// written above the table. Each set states its own where it is lifted.
    @Test("Efforts written on two different scales are not spanned")
    func mixedScalesAreNotSpanned() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.squat, displayName: "Squat",
            sets: [
                SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "8")),
                SetPrescription(
                    intensity: IntensityTarget(scale: .percentOfOneRepMax, value: "80")),
            ],
            repRange: "5")) == "2 × 5")
    }

    /// The last set is lighter and taken to failure. "AMRAP" is not a rep count
    /// and nothing pretends it is one, so both targets are named — and the
    /// target having already said these sets differ, the line does not spend its
    /// remaining room saying it again with the load.
    @Test("A drop set names both targets it asks for")
    func dropSetNamesBothTargets() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench",
            sets: [
                SetPrescription(),
                SetPrescription(),
                SetPrescription(),
                SetPrescription(repRange: "AMRAP", suggestedLoad: kg(70)),
            ],
            repRange: "8", suggestedLoad: kg(100))) == "4 × 8/AMRAP")
    }

    /// One thing beside the count and the target, because one is what the row
    /// holds beside the rest it prescribes. Where the sets differ in load, that
    /// is the thing: the effort is on each row's own field under the bar.
    @Test("A ramp that also states an effort spends its one line on the load")
    func loadWinsTheLineOverEffort() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.squat, displayName: "Squat",
            sets: [
                SetPrescription(
                    suggestedLoad: kg(60), intensity: IntensityTarget(scale: .rpe, value: "7")),
                SetPrescription(
                    suggestedLoad: kg(80), intensity: IntensityTarget(scale: .rpe, value: "9")),
            ],
            repRange: "5")) == "2 × 5 · 60-80 kg")
    }

    @Test("A load span is read in the unit the lifter reads everything else in")
    func loadSpanIsConvertedForDisplay() throws {
        let line = try imported(
            PlanDocumentExercise(
                exerciseID: Self.squat, displayName: "Squat",
                sets: [
                    SetPrescription(suggestedLoad: Mass(value: 135, unit: .pounds)),
                    SetPrescription(suggestedLoad: Mass(value: 225, unit: .pounds)),
                ],
                repRange: "5"),
            unit: .pounds)

        #expect(line == "2 × 5 · 135-225 lb")
    }

    /// A set nobody prescribed a target for is an absence, and a span across it
    /// would be claiming a target it was never given.
    @Test("A count alone is stated when a set was given no target at all")
    func aSetWithNoTargetLeavesOnlyTheCount() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench", sets: 4)) == "4 sets")

        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Bench",
            sets: [SetPrescription(repRange: "8"), SetPrescription()])) == "2 sets")
    }

    // MARK: - Work that is held or carried

    @Test("A hold reads as the hold it was written as")
    func holdsReadAsHolds() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.plank, displayName: "Front Plank", sets: 3,
            repRange: "45 seconds")) == "3 × 45 seconds")

        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.plank, displayName: "Front Plank",
            sets: [
                SetPrescription(repRange: "30 seconds"),
                SetPrescription(repRange: "45 seconds"),
                SetPrescription(repRange: "1 min"),
            ])) == "3 × 30-60s")
    }

    @Test("A carry keeps the unit it was prescribed in, and never converts one")
    func carriesKeepTheirUnit() throws {
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.carry, displayName: "Farmer's Carry", sets: 3,
            repRange: "40 m", suggestedLoad: kg(32))) == "3 × 40 m")

        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.carry, displayName: "Farmer's Carry",
            sets: [
                SetPrescription(repRange: "40 m"),
                SetPrescription(repRange: "60 m"),
            ])) == "2 × 40-60 m")

        // Metres and yards are two measurements, and no span covers both.
        #expect(try imported(PlanDocumentExercise(
            exerciseID: Self.carry, displayName: "Farmer's Carry",
            sets: [
                SetPrescription(repRange: "40 m"),
                SetPrescription(repRange: "50 yd"),
            ])) == "2 × 40 m/50 yd")
    }

    // MARK: - Inside a group

    /// A movement inside a superset is written by the same function as one
    /// performed on its own — the group says how many rounds and how long to
    /// rest, and the movement says what it asks for, in one line either way.
    @Test("A movement inside a superset reads as one line, like any other")
    func groupedMovementReadsTheSameWay() throws {
        let day = PlanDocumentDay(
            weekday: .monday,
            entries: [
                .group(PlanDocumentGroup(
                    exercises: [
                        PlanDocumentExercise(
                            exerciseID: Self.bench, displayName: "Bench",
                            sets: [
                                SetPrescription(suggestedLoad: kg(60)),
                                SetPrescription(suggestedLoad: kg(70)),
                            ],
                            repRange: "12-15"),
                        PlanDocumentExercise(
                            exerciseID: Self.squat, displayName: "Squat", sets: 3,
                            repRange: "12-15"),
                    ],
                    restSeconds: 90))
            ])

        #expect(try line(for: day) == "2 × 12-15 · 60-70 kg")
    }
}
