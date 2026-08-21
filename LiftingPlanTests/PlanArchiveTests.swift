import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A watcher a test drives by hand, so an arrival happens when it says so.
@MainActor
private final class ManualWatcher: DocumentArrivalWatching {
    private var onArrival: (@MainActor () async -> Void)?
    func start(onArrival: @escaping @MainActor () async -> Void) { self.onArrival = onArrival }
    func stop() {}
    func announceArrival() async { await onArrival?() }
}

/// That a plan the app took in is still readable after the next one replaces it.
///
/// **The defect this closes.** Every `Session` records the `sourceDocumentID` of
/// the document that prescribed it, and that ID was stored, exported to the
/// coach and reconstructed on the way back — while pointing at nothing.
/// `plan.json` is replaced by the next plan the coach writes, so the document a
/// session named had ceased to exist anywhere. `CLAUDE.md` and `docs/decided.md`
/// both described the archive that fixes it; nothing wrote it.
///
/// `PlanArchiveTests` in LiftingKit covers the folder's own behaviour. This
/// covers the decision above it: *which* documents get kept.
@MainActor
@Suite("A plan taken in is kept")
struct PlanArchiveTests {

    private func folder() throws -> DocumentFolder {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DocumentFolder(directory: url)
    }

    /// Puts `plan` in the folder, announces it, and hands back the folder.
    private func afterImporting(
        _ plan: PlanDocument, into context: ModelContext? = nil
    ) async throws -> (DocumentFolder, DocumentInbox) {
        let folder = try folder()
        try folder.writePlan(plan)
        let watcher = ManualWatcher()
        let inbox = DocumentInbox(
            transport: folder, watcher: watcher,
            context: try context ?? ModelContext(try StoreContainer.inMemory()),
            catalog: try ExerciseCatalog.bundled())
        inbox.start()
        await watcher.announceArrival()
        return (folder, inbox)
    }

    @Test("Importing a plan keeps it, under the ID its sessions record")
    func anImportedPlanIsKept() async throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = StoreFixture.plan(blocks: 1, sessionsPerBlock: 2)

        let (folder, inbox) = try await afterImporting(plan, into: context)

        #expect(inbox.errorMessage == nil)
        let kept = try #require(try folder.archivedPlans().first)
        #expect(kept.id == plan.id)

        // The pointer resolves: every session names a document that is there.
        let stored = try StoreFixture.sessions(in: context)
        #expect(!stored.isEmpty)
        for session in stored {
            #expect(session.sourceDocumentID == kept.id)
        }
    }

    @Test("The plan survives the next one replacing plan.json")
    func anEarlierPlanOutlivesTheLiveDocument() async throws {
        // This is the whole point: the live file is a mailbox, not a record.
        let context = ModelContext(try StoreContainer.inMemory())
        let first = StoreFixture.plan(blocks: 1, sessionsPerBlock: 1)
        let (folder, _) = try await afterImporting(first, into: context)

        let second = StoreFixture.plan(blocks: 1, sessionsPerBlock: 3)
        try folder.writePlan(second)
        try folder.archivePlan(second)

        let kept = try folder.archivedPlans()
        #expect(kept.count == 2)
        #expect(kept.contains { $0.id == first.id }, "the replaced plan is still readable")
    }

    @Test("A refused plan is not kept")
    func aRefusedPlanIsNotKept() async throws {
        // The archive is what `sourceDocumentID` points at, so it holds every
        // document that produced sessions and nothing else. A plan naming an
        // exercise the catalog does not have produced none, and keeping it
        // would put prescriptions in the record the lifter was never given.
        let plan = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push",
                entries: [.exercise(PlanDocumentExercise(
                    exerciseID: ExerciseID(rawValue: "not-a-real-exercise"),
                    displayName: "", sets: [StoreFixture.set()]))])])

        let (folder, inbox) = try await afterImporting(plan)

        #expect(inbox.errorMessage != nil, "the lifter is told")
        #expect(try folder.archivedPlans().isEmpty)
    }

    @Test("Re-announcing the same plan keeps one copy")
    func reAnnouncingKeepsOneCopy() async throws {
        // The folder is announced whenever anything in it changes, including
        // the snapshot this app writes back into it.
        let context = ModelContext(try StoreContainer.inMemory())
        let plan = StoreFixture.plan()
        let folder = try folder()
        try folder.writePlan(plan)
        let watcher = ManualWatcher()
        let inbox = DocumentInbox(
            transport: folder, watcher: watcher, context: context,
            catalog: try ExerciseCatalog.bundled())
        inbox.start()

        await watcher.announceArrival()
        await watcher.announceArrival()
        await watcher.announceArrival()

        #expect(inbox.errorMessage == nil)
        #expect(try folder.archivedPlans().count == 1)
    }
}
