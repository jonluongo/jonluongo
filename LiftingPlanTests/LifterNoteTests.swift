import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What the lifter writes about performing a movement, and how it reaches the
/// coach.
///
/// **Two notes, two fields, on purpose.** The coach's is part of the
/// prescription — extra detail on the work he asked for — and arrives with every
/// plan. The lifter's is part of what happened: *knee hurt at the end*. Sharing
/// one field would mean whichever of them wrote last erased the other, and
/// nothing afterwards could say whose sentence it had been.
@Suite("The lifter's own note")
@MainActor
struct LifterNoteTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// A block of one movement, imported the way one really arrives.
    private func imported(
        coachNote: String? = nil, into context: ModelContext
    ) throws -> PlannedExercise {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Autumn",
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", exercises: [
                PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: 3, repRange: "5", notes: coachNote)
            ])])
        let plan = try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        return try #require(plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)
    }

    private func exported(_ context: ModelContext) throws -> TrainingSnapshot {
        try SnapshotExporter.export(from: context, catalogVersion: 5, generatedAt: Self.instant)
    }

    @Test("A note the lifter writes reaches the coach in his own words")
    func noteReachesTheCoach() throws {
        let context = try context()
        let exercise = try imported(into: context)

        exercise.lifterNote = "Knee hurt at the end."
        try context.saveOrThrow()

        let note = try #require(try exported(context).lifterNotes.first)
        #expect(note.text == "Knee hurt at the end.")
        #expect(note.exerciseID == Self.bench)
        #expect(note.weekOrdinal == 1)
        #expect(note.weekday == .monday)
        #expect(note.exerciseOrder == 0)
    }

    @Test("The two notes are two fields: neither writes over the other")
    func theTwoNotesAreSeparate() throws {
        let context = try context()
        let exercise = try imported(coachNote: "Pause the last rep.", into: context)

        exercise.lifterNote = "Shoulder felt off."
        try context.saveOrThrow()

        // The coach's stays inside the plan document he wrote; the lifter's
        // travels beside the log, because it is part of what happened.
        let snapshot = try exported(context)
        #expect(snapshot.firstPrescribedExercise?.notes == "Pause the last rep.")
        #expect(snapshot.lifterNotes.first?.text == "Shoulder felt off.")
    }

    @Test("A movement he wrote nothing about carries no note at all")
    func nothingWrittenIsNoNote() throws {
        let context = try context()
        _ = try imported(coachNote: "Pause the last rep.", into: context)

        #expect(try exported(context).lifterNotes.isEmpty)
    }

    @Test("A note emptied is a note gone, not an empty one kept")
    func emptiedNoteIsGone() throws {
        let context = try context()
        let exercise = try imported(into: context)
        exercise.lifterNote = "Knee hurt."
        try context.saveOrThrow()

        exercise.lifterNote = nil
        try context.saveOrThrow()

        #expect(try exported(context).lifterNotes.isEmpty)
    }

    @Test("A new plan replaces the coach's note and leaves the lifter's alone")
    func aNewPlanDoesNotEraseHisWords() throws {
        // The blocks are different documents, so this is really the guarantee
        // that his words live on the record rather than on the prescription: a
        // note written against a block that has been superseded is still in the
        // snapshot, under the block it was written in.
        let context = try context()
        let exercise = try imported(coachNote: "Pause the last rep.", into: context)
        exercise.lifterNote = "Knee hurt at the end."
        try context.saveOrThrow()

        _ = try imported(coachNote: "Touch and go.", into: context)

        let snapshot = try exported(context)
        #expect(snapshot.routines.count == 2)
        #expect(snapshot.lifterNotes.count == 1)
        #expect(snapshot.lifterNotes.first?.text == "Knee hurt at the end.")
    }
}
