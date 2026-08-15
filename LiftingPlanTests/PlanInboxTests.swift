import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A watcher that fires when a test tells it to, standing in for iCloud
/// announcing that a file arrived.
@MainActor
private final class ManualPlanWatcher: PlanArrivalWatching {
    private var onArrival: (() -> Void)?
    private(set) var isWatching = false

    func start(onArrival: @escaping () -> Void) {
        self.onArrival = onArrival
        isWatching = true
    }

    func stop() {
        isWatching = false
    }

    /// Announces an arrival the way iCloud would.
    func announceArrival() {
        onArrival?()
    }
}

@MainActor
@Suite("Plan inbox")
struct PlanInboxTests {

    // MARK: - Fixtures

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let benchPress = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// The real bundled catalog: the import's one check is that an exercise
    /// exists, so a fixture catalog would test the fixture.
    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func temporaryFolder() throws -> DocumentFolder {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DocumentFolder(directory: url)
    }

    private func document(
        id: UUID = UUID(),
        exerciseID: ExerciseID = PlanInboxTests.benchPress
    ) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant,
            title: "Strength block", goal: "Bigger bench", weekCount: 4,
            durationMinutes: 60,
            days: [
                PlanDocumentDay(
                    weekday: .monday, focus: "Push", durationMinutes: 60,
                    exercises: [
                        PlanDocumentExercise(
                            exerciseID: exerciseID, displayName: "Barbell Bench Press",
                            sets: 3, repRange: "5", restSeconds: 180,
                            suggestedLoad: Mass(value: 225, unit: .pounds)
                        )
                    ]
                )
            ]
        )
    }

    private func inbox(
        transport: any DocumentTransport,
        watcher: ManualPlanWatcher,
        context: ModelContext
    ) throws -> PlanInbox {
        PlanInbox(
            transport: transport, watcher: watcher, context: context, catalog: try catalog()
        )
    }

    private func storedPlans(in context: ModelContext) throws -> [TrainingPlan] {
        try context.fetch(FetchDescriptor<TrainingPlan>())
    }

    // MARK: - A plan that arrives is imported

    @Test("A plan that arrives is imported without the lifter asking for it")
    func arrivingPlanIsImported() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        let written = document()
        try folder.writePlan(written)

        inbox.start()
        watcher.announceArrival()

        let plans = try storedPlans(in: context)
        #expect(plans.count == 1)
        #expect(plans.first?.sourceDocumentID == written.id)
        #expect(inbox.errorMessage == nil)
    }

    @Test("Starting the inbox begins watching, so nothing has to be pulled to refresh")
    func startingBeginsWatching() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()

        #expect(watcher.isWatching)
    }

    @Test("Stopping the inbox stops the watch")
    func stoppingEndsWatching() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()
        inbox.stop()

        #expect(!watcher.isWatching)
    }

    @Test("The same plan arriving twice imports once rather than duplicating a block")
    func sameplanArrivingTwiceImportsOnce() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        try folder.writePlan(document())

        inbox.start()
        watcher.announceArrival()
        watcher.announceArrival()

        #expect(try storedPlans(in: context).count == 1)
    }

    // MARK: - Absence is normal, corruption is not

    @Test("No plan yet is the ordinary state, not an error to show the lifter")
    func noPlanYetIsNotAnError() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        watcher.announceArrival()

        #expect(try storedPlans(in: context).isEmpty)
        #expect(inbox.errorMessage == nil)
    }

    @Test("A malformed plan surfaces an error rather than passing for no plan at all")
    func malformedPlanSurfacesAnError() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("{ this is not a plan".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.planFilename))
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
        #expect(try storedPlans(in: context).isEmpty)
    }

    @Test("A plan naming an exercise the catalog lacks reports which one, and imports nothing")
    func unknownExerciseSurfacesTheOffendingID() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.writePlan(document(exerciseID: ExerciseID(rawValue: "moon-press")))
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        watcher.announceArrival()

        let message = try #require(inbox.errorMessage)
        #expect(message.contains("moon-press"))
        #expect(try storedPlans(in: context).isEmpty)
    }

    @Test("Dismissing the error clears it, so a fixed plan is not reported against")
    func dismissingClearsTheError() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("not a plan".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.planFilename))
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()
        watcher.announceArrival()
        inbox.dismissError()

        #expect(inbox.errorMessage == nil)
    }

    @Test("A transport that cannot reach its container reports it rather than staying quiet")
    func unreachableTransportReportsItself() throws {
        let transport = ICloudDocumentTransport(
            containerIdentifier: "iCloud.com.jonluongo.LiftingPlan",
            resolveContainer: { _ in nil }
        )
        let context = try context()
        let watcher = ManualPlanWatcher()
        let inbox = try inbox(transport: transport, watcher: watcher, context: context)

        inbox.start()
        watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
        #expect(try storedPlans(in: context).isEmpty)
    }
}
