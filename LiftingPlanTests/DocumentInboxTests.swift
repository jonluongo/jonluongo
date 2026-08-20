import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// A watcher that fires when a test tells it to, standing in for iCloud
/// announcing that a file arrived.
@MainActor
private final class ManualArrivalWatcher: DocumentArrivalWatching {
    private var onArrival: (@MainActor () async -> Void)?
    private(set) var isWatching = false

    func start(onArrival: @escaping @MainActor () async -> Void) {
        self.onArrival = onArrival
        isWatching = true
    }

    func stop() {
        isWatching = false
    }

    /// Announces an arrival the way iCloud would, and returns once the
    /// handler has finished — the real watcher does not wait, but a test that
    /// did not would be reading a result that has not happened yet.
    func announceArrival() async {
        await onArrival?()
    }
}

@MainActor
@Suite("Document inbox")
struct DocumentInboxTests {

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
        exerciseID: ExerciseID = DocumentInboxTests.benchPress
    ) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant,
            title: "Strength block", goal: "Bigger bench",
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
        watcher: ManualArrivalWatcher,
        context: ModelContext
    ) throws -> DocumentInbox {
        DocumentInbox(
            transport: transport, watcher: watcher, context: context, catalog: try catalog()
        )
    }

    private func storedPlans(in context: ModelContext) throws -> [TrainingPlan] {
        try context.fetch(FetchDescriptor<TrainingPlan>())
    }

    // MARK: - What lands goes back out

    @Test("A plan that lands sends the record back out, so the coach is never behind it")
    func arrivalSendsTheRecordBack() async throws {
        // The failure this closes: the snapshot was written only when the app
        // backgrounded, so a plan that arrived while the lifter had the app
        // open left the coach reading a record written before it existed.
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())
        var sent = 0
        inbox.onApplied = { sent += 1 }
        try folder.writePlan(document())

        inbox.start()
        await watcher.announceArrival()

        #expect(sent == 1)
    }

    @Test("A folder announcing itself again sends nothing, so the two halves cannot loop")
    func reannouncementSendsNothing() async throws {
        // The snapshot is written into the folder this watches, so an export
        // announces an arrival. If a document merely re-announced counted as
        // one that landed, the inbox and the outbox would write to each other
        // forever.
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())
        var sent = 0
        inbox.onApplied = { sent += 1 }
        try folder.writePlan(document())

        inbox.start()
        await watcher.announceArrival()
        await watcher.announceArrival()
        await watcher.announceArrival()

        #expect(sent == 1, "only the arrival that changed the record sends")
    }

    @Test("Next week's block landing on a routine counts as an arrival")
    func agrownRoutineIsAnArrival() async throws {
        // The failure this closes is the one the whole loop rests on. A routine
        // grows by arriving again under its own identity, and the inbox used to
        // ask *is this identity already stored* — which is true of every block
        // after the first. The coach would have written next week and read back
        // a snapshot that predated it.
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let context = try context()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        var sent = 0
        inbox.onApplied = { sent += 1 }
        let id = UUID()
        try folder.writePlan(routine(id: id, blocks: 1))

        inbox.start()
        await watcher.announceArrival()
        try folder.writePlan(routine(id: id, blocks: 2))
        await watcher.announceArrival()

        #expect(sent == 2, "the block that arrived is a change and has to go back out")
        #expect(try storedPlans(in: context).count == 1, "one routine, two blocks")
        #expect(try storedPlans(in: context).first?.orderedWeeks.count == 2)
    }

    @Test("A goal the coach revised counts as an arrival, though no block moved")
    func aRevisedGoalIsAnArrival() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let context = try context()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        var sent = 0
        inbox.onApplied = { sent += 1 }
        let id = UUID()
        try folder.writePlan(routine(id: id, blocks: 1))

        inbox.start()
        await watcher.announceArrival()
        try folder.writePlan(routine(id: id, blocks: 1, goal: "Bench 245"))
        await watcher.announceArrival()

        #expect(sent == 2, "the record has to go back out saying what it is for now")
        #expect(try storedPlans(in: context).first?.goal == "Bench 245")
    }

    /// A routine of `blocks` blocks under one identity, each one Monday push
    /// session — the shape a week-at-a-time coach writes.
    private func routine(id: UUID, blocks: Int, goal: String = "") -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant, title: "Strength block",
            goal: goal,
            blocks: (1...blocks).map { ordinal in
                PlanDocumentBlock(label: "Block \(ordinal)", days: [
                    PlanDocumentDay(
                        weekday: .monday, focus: "Push",
                        exercises: [
                            PlanDocumentExercise(
                                exerciseID: Self.benchPress, displayName: "Barbell Bench Press",
                                sets: 3, repRange: "5", restSeconds: 180,
                                suggestedLoad: Mass(value: 225, unit: .pounds))
                        ])
                ])
            })
    }

    @Test("An empty folder sends nothing")
    func nothingWaitingSendsNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())
        var sent = 0
        inbox.onApplied = { sent += 1 }

        inbox.start()
        await watcher.announceArrival()

        #expect(sent == 0)
    }

    @Test("A document that was refused sends nothing, because nothing changed")
    func refusedDocumentSendsNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())
        var sent = 0
        inbox.onApplied = { sent += 1 }
        try folder.writePlan(document(exerciseID: ExerciseID(rawValue: "not-a-real-exercise")))

        inbox.start()
        await watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
        #expect(sent == 0)
    }

    // MARK: - A plan that arrives is imported

    @Test("A plan that arrives is imported without the lifter asking for it")
    func arrivingPlanIsImported() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        let written = document()
        try folder.writePlan(written)

        inbox.start()
        await watcher.announceArrival()

        let plans = try storedPlans(in: context)
        #expect(plans.count == 1)
        #expect(plans.first?.sourceDocumentID == written.id)
        #expect(inbox.errorMessage == nil)
    }

    @Test("Starting the inbox begins watching, so nothing has to be pulled to refresh")
    func startingBeginsWatching() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()

        #expect(watcher.isWatching)
    }

    @Test("Stopping the inbox stops the watch")
    func stoppingEndsWatching() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()
        inbox.stop()

        #expect(!watcher.isWatching)
    }

    @Test("The same plan arriving twice imports once rather than duplicating a block")
    func sameplanArrivingTwiceImportsOnce() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        try folder.writePlan(document())

        inbox.start()
        await watcher.announceArrival()
        await watcher.announceArrival()

        #expect(try storedPlans(in: context).count == 1)
    }

    // MARK: - Absence is normal, corruption is not

    @Test("No plan yet is the ordinary state, not an error to show the lifter")
    func noPlanYetIsNotAnError() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        #expect(try storedPlans(in: context).isEmpty)
        #expect(inbox.errorMessage == nil)
    }

    @Test("A malformed plan surfaces an error rather than passing for no plan at all")
    func malformedPlanSurfacesAnError() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("{ this is not a plan".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.planFilename))
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
        #expect(try storedPlans(in: context).isEmpty)
    }

    @Test("A plan naming an exercise the catalog lacks reports which one, and imports nothing")
    func unknownExerciseSurfacesTheOffendingID() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.writePlan(document(exerciseID: ExerciseID(rawValue: "moon-press")))
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        let message = try #require(inbox.errorMessage)
        #expect(message.contains("moon-press"))
        #expect(try storedPlans(in: context).isEmpty)
    }

    @Test("Dismissing the error clears it, so a fixed plan is not reported against")
    func dismissingClearsTheError() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("not a plan".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.planFilename))
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: try context())

        inbox.start()
        await watcher.announceArrival()
        inbox.dismissError()

        #expect(inbox.errorMessage == nil)
    }

    @Test("A transport that cannot reach its container reports it rather than staying quiet")
    func unreachableTransportReportsItself() async throws {
        let transport = ICloudDocumentTransport(
            containerIdentifier: "iCloud.com.jonluongo.LiftingPlan",
            resolveContainer: { _ in nil }
        )
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: transport, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        let message = try #require(inbox.errorMessage)
        #expect(try storedPlans(in: context).isEmpty)
        // One unreachable container is one problem, not two, even though both
        // reads failed on it.
        #expect(!message.contains("\n\n"))
    }

    // MARK: - A profile update arrives the same way a plan does

    private func storedProfiles(in context: ModelContext) throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>())
    }

    private func profileUpdate(id: UUID = UUID()) -> ProfileUpdate {
        ProfileUpdate(
            id: id, generatedAt: Self.instant, displayUnit: .stated(.pounds),
            experience: .stated(.advanced), equipment: .stated([.dumbbell, .plate]),
            goal: .stated("Bigger bench")
        )
    }

    @Test("A profile update that arrives is applied, not merely received")
    func arrivingProfileUpdateIsApplied() async throws {
        // The failure this guards is silent: an update that lands in the folder
        // and never reaches the store leaves the snapshot reporting the old
        // facts, so Claude believes he recorded something he did not.
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        try folder.writeProfileUpdate(profileUpdate())

        inbox.start()
        await watcher.announceArrival()

        let profile = try #require(try storedProfiles(in: context).first)
        #expect(profile.experience == .advanced)
        #expect(profile.ownedEquipment.map(Set.init) == [.dumbbell, .plate])
        #expect(profile.goal == "Bigger bench")
        #expect(inbox.errorMessage == nil)
    }

    @Test("A plan and a profile update waiting together both land in one pass")
    func bothDocumentsLandTogether() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        try folder.writePlan(document())
        try folder.writeProfileUpdate(profileUpdate())

        inbox.start()
        await watcher.announceArrival()

        #expect(try storedPlans(in: context).count == 1)
        #expect(try storedProfiles(in: context).first?.experience == .advanced)
    }

    @Test("An unreadable plan does not stop a perfectly good profile update landing")
    func oneBadDocumentDoesNotBlockTheOther() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("{ this is not a plan".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.planFilename))
        try folder.writeProfileUpdate(profileUpdate())
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
        #expect(try storedProfiles(in: context).first?.experience == .advanced)
    }

    @Test("A malformed profile update surfaces an error rather than passing for none at all")
    func malformedProfileUpdateSurfacesAnError() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try Data("{ not an update".utf8)
            .write(to: folder.url.appending(path: DocumentFolder.profileUpdateFilename))
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)

        inbox.start()
        await watcher.announceArrival()

        #expect(inbox.errorMessage != nil)
    }

    @Test("The same update arriving twice is applied once, so a later change is not undone")
    func sameUpdateArrivingTwiceAppliesOnce() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let watcher = ManualArrivalWatcher()
        let inbox = try inbox(transport: folder, watcher: watcher, context: context)
        try folder.writeProfileUpdate(profileUpdate())

        inbox.start()
        await watcher.announceArrival()
        // Something the lifter changed for himself after the update landed.
        let profile = try #require(try storedProfiles(in: context).first)
        profile.displayUnit = .kilograms
        try context.saveOrThrow()
        await watcher.announceArrival()

        #expect(try storedProfiles(in: context).count == 1)
        #expect(try storedProfiles(in: context).first?.displayUnit == .kilograms)
    }
}
