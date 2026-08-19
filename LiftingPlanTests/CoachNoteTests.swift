import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The coach's own words about a block, from the document he wrote to the record
/// the lifter opens and the snapshot he reads back.
///
/// The gap these close is the one an audit found by accident: `PlanDocument`
/// carried `notes` — a block-level note in the coach's words — and the mapping
/// into the store dropped it on the floor. Nothing refused it, nothing reported
/// it, and nobody ever saw it. It is the most distinctive content in the
/// product, so each test below stands at one point on the path it now takes.
///
/// The same sweep found `generatedAt` going the same way: the document says when
/// the plan was written, the store recorded only when it arrived, and the two are
/// not the same date. Both are here because both are the same failure.
@Suite("The coach's words through the app")
struct CoachNoteTests {

    private static let written = Date(timeIntervalSince1970: 1_700_000_000)
    private static let arrived = Date(timeIntervalSince1970: 1_700_086_400)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let note = """
        Three heavy weeks then a deload. If the left shoulder complains on the \
        bench, stop the set and tell me.
        """

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    /// A block of one movement, with whatever block-level facts the test is
    /// about.
    private static func document(
        title: String = "Autumn strength", notes: String? = nil
    ) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: written, title: title,
            goal: "Bigger bench", durationMinutes: 60, notes: notes,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Push",
                exercises: [PlanDocumentExercise(
                    exerciseID: bench, displayName: "Barbell Bench Press",
                    sets: 3, repRange: "5", restSeconds: 180)])]
        )
    }

    private func imported(_ document: PlanDocument) throws -> (TrainingPlan, ModelContext) {
        let context = try context()
        let plan = try PlanImporter.import(
            document, into: context, catalog: try catalog(), importedAt: Self.arrived)
        return (plan, context)
    }

    // MARK: - The note crosses into the app's own vocabulary

    @Test("A note the coach wrote reaches the blueprint")
    func noteReachesTheBlueprint() {
        let blueprint = RoutineBlueprint(document: Self.document(notes: Self.note))

        #expect(blueprint.notes == Self.note)
    }

    @Test("A block the coach said nothing about has no note, not an empty one")
    func absentNoteStaysAbsent() {
        #expect(RoutineBlueprint(document: Self.document()).notes == nil)
    }

    // MARK: - And into the store

    @Test("A note the coach wrote reaches the store")
    func noteReachesTheStore() throws {
        let (plan, _) = try imported(Self.document(notes: Self.note))

        #expect(plan.notes == Self.note)
    }

    @Test("A note is stored exactly as written, not trimmed or shortened")
    func noteIsStoredVerbatim() throws {
        let stated = "  Deload week 4. Rest as long as you need.\n"
        let (plan, _) = try imported(Self.document(notes: stated))

        #expect(plan.notes == stated)
    }

    @Test("A note the coach deliberately left empty stays empty rather than absent")
    func emptyNoteIsRecordedAsWritten() throws {
        let (plan, _) = try imported(Self.document(notes: ""))

        #expect(plan.notes == "", "an empty note is what he wrote; nothing may read it as absent")
    }

    @Test("A block with no note stores none")
    func storeKeepsAbsenceAbsent() throws {
        let (plan, _) = try imported(Self.document())

        #expect(plan.notes == nil)
    }

    // MARK: - And back out to the coach who wrote it

    @Test("The note reaches the snapshot the coach reads back")
    func noteReachesTheSnapshot() throws {
        let (_, context) = try imported(Self.document(notes: Self.note))

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(snapshot.firstDocument?.notes == Self.note)
    }

    @Test("The note survives the snapshot's own encoding, under its own key")
    func noteSurvivesEncoding() throws {
        let (_, context) = try imported(Self.document(notes: Self.note))
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)

        #expect(decoded.firstDocument?.notes == Self.note)
        #expect(String(decoding: data, as: UTF8.self).contains("\"notes\""))
    }

    @Test("A block with no note reports none rather than an empty string")
    func snapshotKeepsAbsenceAbsent() throws {
        let (_, context) = try imported(Self.document())

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(snapshot.firstDocument?.notes == nil)
    }

    // MARK: - The block's name

    @Test("The block's title reaches the store and the snapshot")
    func titleIsCarried() throws {
        let (plan, context) = try imported(Self.document(title: "Autumn strength"))

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(plan.title == "Autumn strength")
        #expect(snapshot.firstDocument?.title == "Autumn strength")
    }

    @Test("A block the coach did not name has an empty title, never an invented one")
    func unnamedBlockStaysUnnamed() throws {
        let (plan, _) = try imported(Self.document(title: ""))

        #expect(plan.title == "")
    }

    // MARK: - When it was written, beside when it arrived

    @Test("When the plan was written is recorded beside when it arrived")
    func writtenDateIsRecorded() throws {
        let (plan, _) = try imported(Self.document(notes: Self.note))

        #expect(plan.generatedAt == Self.written)
        #expect(plan.startDate == Self.arrived)
        #expect(plan.generatedAt != plan.startDate, "written and arrived are different days")
    }

    @Test("A block that did not arrive as a document says nothing about when it was written")
    func blockWithNoDocumentHasNoWrittenDate() throws {
        let plan = RoutineBlueprint(weeks: []).makeWorkoutPlan(catalogVersion: 5)

        #expect(plan.generatedAt == nil)
    }

    @Test("When the plan was written reaches the snapshot")
    func writtenDateReachesTheSnapshot() throws {
        let (_, context) = try imported(Self.document(notes: Self.note))

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        // When it was written is the document's own; when it arrived is the
        // record's, and sits beside the document rather than inside it.
        #expect(snapshot.firstDocument?.generatedAt == Self.written)
        #expect(snapshot.routines.first?.startDate == Self.arrived)
    }
}
