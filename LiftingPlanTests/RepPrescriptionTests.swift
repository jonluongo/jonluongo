import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The prescribed rep target has to reach the lifter unaltered.
///
/// This is the surviving twin of the deleted `seedLoad`: the workout view used
/// to seed each set's reps from what the lifter did in his *last* session,
/// falling back to the top of the prescribed range, so on any exercise with
/// history Claude's prescription never appeared at all. These tests pin both
/// halves — history is never substituted, and neither end of a range is picked.
@Suite("Rep prescription")
struct RepPrescriptionTests {

    // MARK: - What a prescription seeds

    @Test("A target naming one number seeds that number")
    func singleNumberSeeds() {
        #expect(RepPrescription.seededReps(for: "5") == 5)
        #expect(RepPrescription.seededReps(for: "12") == 12)
    }

    @Test("A range seeds nothing — picking an end of it is a training decision")
    func rangeSeedsNothing() {
        // "8-12" prescribes a range, not a rep count. Seeding 12 tells the
        // lifter to hit the top every set; seeding 8 tells him the bottom.
        // The app says neither.
        #expect(RepPrescription.seededReps(for: "8-12") == nil)
        #expect(RepPrescription.seededReps(for: "8 to 12") == nil)
        #expect(RepPrescription.seededReps(for: "5-3-1") == nil)
    }

    @Test("No target seeds nothing, rather than zero reps")
    func absentTargetSeedsNothing() {
        // `RepRange` reads no digits out of these, which used to come back as
        // `upperBound == 0` and seed every set to 0 reps.
        #expect(RepPrescription.seededReps(for: "") == nil)
        #expect(RepPrescription.seededReps(for: "AMRAP") == nil)
    }

    // MARK: - What an empty field shows

    @Test("An empty field shows the prescription exactly as the plan wrote it")
    func targetTextIsThePrescription() {
        #expect(RepPrescription.targetText(for: "8-12") == "8-12")
        #expect(RepPrescription.targetText(for: "AMRAP") == "AMRAP")
        #expect(RepPrescription.targetText(for: " 5 ") == "5")
    }

    @Test("A prescription that names no target shows an em dash, not a zero")
    func targetTextForNoPrescription() {
        #expect(RepPrescription.targetText(for: "") == "")
        #expect(RepPrescription.targetText(for: "   ") == "")
    }

    // MARK: - The regression itself

    @Test("Seeding ignores history entirely — last session's reps are reference, not target")
    func historyIsNeverSubstituted() throws {
        // The bug: Claude prescribes 5, the lifter did 8 last week, the app
        // pre-fills 8 and the lifter reads a pre-filled number as the target.
        // Seeding takes no history argument at all now, so there is nowhere
        // for last week's 8 to come from.
        let context = ModelContext(try StoreContainer.inMemory())
        let previous = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", order: 0, targetSets: 3, repRange: "5"
        )
        previous.loggedSets = [
            LoggedSet(setIndex: 0, load: Mass(value: 60, unit: .kilograms), reps: 8, isCompleted: true),
            LoggedSet(setIndex: 1, load: Mass(value: 60, unit: .kilograms), reps: 8, isCompleted: true),
        ]
        context.insert(previous)
        try context.saveOrThrow()

        #expect(RepPrescription.seededReps(for: "5") == 5)
        #expect(previous.completedWorkingSets.map(\.reps) == [8, 8])
    }
}
