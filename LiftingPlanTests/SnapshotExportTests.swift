import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What the coach is told the record holds.
///
/// **The report that started this.** The coach was told a block held four
/// sessions when it held nine — Push weeks one to three, Pull missing entirely.
/// A snapshot that under-reports is the one failure that arrives looking like a
/// fact: it does not look like an error, it looks like a user who has trained
/// less than he has, and the next plan is written against it.
///
/// So the first thing here builds more than fits in one fetch batch and counts
/// what comes out.
@Suite("What the coach is told")
struct SnapshotExportTests {

    private func exported(_ context: ModelContext) throws -> TrainingSnapshot {
        try SnapshotExporter.export(
            from: context, catalogVersion: 5, exportedAt: StoreFixture.instant)
    }

    @Test("Every session of every block survives the export, with its exercises")
    func nothingIsDropped() throws {
        let context = try StoreFixture.imported(
            StoreFixture.plan(blocks: 3, sessionsPerBlock: 3))

        let snapshot = try exported(context)

        #expect(snapshot.sessions.count == 9, "three blocks of three")
        #expect(snapshot.blockOrdinals == [1, 2, 3])
        for block in 1...3 {
            #expect(snapshot.sessions(inBlock: block).map(\.ordinal) == [1, 2, 3],
                    "block \(block)")
        }
        #expect(
            snapshot.sessions.allSatisfy { !$0.prescription.exercises.isEmpty },
            "a session that arrives without its movements is a session nobody can train")
    }

    @Test("A block of many sessions is not truncated")
    func aLongBlockSurvives() throws {
        // Deliberately past any batch a fetch might return in one go: the
        // original defect looked exactly like a limit somewhere.
        let context = try StoreFixture.imported(
            StoreFixture.plan(blocks: 1, sessionsPerBlock: 40))
        #expect(try exported(context).sessions.count == 40)
    }

    @Test("The prescription reaches the coach as the document he wrote")
    func theDocumentSurvivesTheRoundTrip() throws {
        let written = StoreFixture.plan(entries: [
            .exercise(StoreFixture.exercise(rest: 210, note: "Pause the last rep."))
        ])
        let snapshot = try exported(try StoreFixture.imported(written))
        let carried = try #require(snapshot.firstPrescribedExercise)

        #expect(carried.exerciseID == StoreFixture.bench)
        #expect(carried.restSeconds == 210)
        #expect(carried.coachNote == "Pause the last rep.")
        #expect(carried.sets.count == 3)
        #expect(carried.sets.first?.target == .repetitions(low: 5, high: nil))
    }

    @Test("A session says when it was written and which import it came from")
    func provenanceSurvives() throws {
        let id = UUID()
        let snapshot = try exported(try StoreFixture.imported(StoreFixture.plan(id: id)))
        let session = try #require(snapshot.firstSession)

        #expect(session.generatedAt == StoreFixture.instant)
        #expect(session.sourceDocumentID == id)
        #expect(session.finishedAt == nil, "nothing has been trained")
    }

    @Test("The record says when it was exported")
    func theExportSaysWhenItWasWritten() throws {
        #expect(try exported(try StoreFixture.context()).exportedAt == StoreFixture.instant)
    }

    @Test("A store with nothing in it exports a record with nothing in it")
    func anEmptyStoreExportsEmpty() throws {
        let snapshot = try exported(try StoreFixture.context())
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.performances.isEmpty)
    }
}
