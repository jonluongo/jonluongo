import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What the user says about a movement, and where it lives.
///
/// **His note moved to the record.** It used to sit on `PlannedExercise`, which
/// put his words under the coach's rewrite rules: a note on a session he had not
/// trained went when the coach rewrote the block. It belongs to what happened,
/// so it lives on `PerformedExercise` — and writing one has to create that
/// performance, because a note written before his first set would otherwise have
/// nowhere to go.
@Suite("The user's own note")
struct UserNoteTests {

    @MainActor
    private func log(_ context: ModelContext, _ session: Session) -> SessionLog {
        SessionLog(
            session: session, context: context,
            restTimer: RestTimerModel(),
            restPreferences: RestPreferences())
    }

    private func session() throws -> (ModelContext, Session, PlannedExercise) {
        let context = try StoreFixture.imported(StoreFixture.plan())
        let session = try #require(try StoreFixture.sessions(in: context).first)
        let exercise = try #require(session.orderedExercises.first)
        return (context, session, exercise)
    }

    @MainActor
    @Test("A note written before the first set still has somewhere to go")
    func aNoteBeforeAnySetCreatesThePerformance() throws {
        let (context, session, exercise) = try self.session()
        #expect((session.performedExercises ?? []).isEmpty)

        try log(context, session).writeNote("Shoulder felt fine.", for: exercise)

        let performed = try #require((session.performedExercises ?? []).first)
        #expect(performed.userNote == "Shoulder felt fine.")
        #expect((performed.sets ?? []).isEmpty, "he wrote before he lifted")
    }

    @MainActor
    @Test("Clearing a note he wrote before lifting leaves nothing behind")
    func clearingRemovesAnEmptyPerformance() throws {
        // An empty performance would put a session in the coach's history that
        // the user never trained.
        let (context, session, exercise) = try self.session()
        let log = log(context, session)

        try log.writeNote("Typed by mistake.", for: exercise)
        try log.writeNote(nil, for: exercise)

        #expect((session.performedExercises ?? []).isEmpty)
    }

    @MainActor
    @Test("Clearing a note keeps the sets he did")
    func clearingKeepsPerformedSets() throws {
        let (context, session, exercise) = try self.session()
        let log = log(context, session)
        let slot = try #require(SessionOrder.trainingOrder(of: session).first)

        try log.record(slot, load: Mass(value: 100, unit: .kilograms), work: .repetitions(5))
        try log.writeNote("Heavy.", for: exercise)
        try log.writeNote(nil, for: exercise)

        let performed = try #require((session.performedExercises ?? []).first)
        #expect(performed.userNote == nil)
        #expect((performed.sets ?? []).count == 1, "the work happened whatever he said about it")
    }

    @MainActor
    @Test("His words reach the coach")
    func theNoteReachesTheSnapshot() throws {
        let (context, session, exercise) = try self.session()
        try log(context, session).writeNote("Left elbow ached on the last set.", for: exercise)

        let snapshot = try SnapshotExporter.export(
            from: context, catalogVersion: 5, exportedAt: StoreFixture.instant)

        #expect(snapshot.performances.first?.userNote == "Left elbow ached on the last set.")
    }

    @MainActor
    @Test("A rewritten session cannot take his note with it")
    func aRewriteCannotTouchHisWords() throws {
        // This is why the note moved. The coach may rewrite a session nothing
        // has been logged against — and a note is something logged against it.
        let (context, session, exercise) = try self.session()
        try log(context, session).writeNote("Felt strong.", for: exercise)

        #expect(session.hasBeenTrained, "a note is part of the record")
        #expect(throws: PlanImportError.self) {
            try PlanImporter.import(
                StoreFixture.plan(entries: [
                    .exercise(StoreFixture.exercise(StoreFixture.squat))
                ]),
                into: context, catalog: try StoreFixture.catalog())
        }
        #expect((session.performedExercises ?? []).first?.userNote == "Felt strong.")
    }
}
