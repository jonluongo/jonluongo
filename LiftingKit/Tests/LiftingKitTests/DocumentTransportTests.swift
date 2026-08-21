import Foundation
import Testing
@testable import LiftingKit

/// The in-memory stand-in for the transport seam.
///
/// It holds whatever was last written and hands it back, and can be told to
/// fail, so a caller's handling of "nothing yet" and "something is broken" can
/// be tested without a filesystem. Kept here rather than in `Sources` because
/// only tests need it.
private final class InMemoryDocumentTransport: DocumentTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: TrainingSnapshot?
    private var plan: PlanDocument?
    private var profileUpdate: ProfileUpdate?
    private var failure: (any Error)?

    struct Broken: Error {}

    init(
        snapshot: TrainingSnapshot? = nil, plan: PlanDocument? = nil,
        profileUpdate: ProfileUpdate? = nil
    ) {
        self.snapshot = snapshot
        self.plan = plan
        self.profileUpdate = profileUpdate
    }

    func breakTransport() {
        lock.withLock { failure = Broken() }
    }

    func writeSnapshot(_ snapshot: TrainingSnapshot) throws {
        try lock.withLock {
            if let failure { throw failure }
            self.snapshot = snapshot
        }
    }

    func readPlan() throws -> PlanDocument? {
        try lock.withLock {
            if let failure { throw failure }
            return plan
        }
    }

    func readSnapshot() throws -> TrainingSnapshot? {
        try lock.withLock {
            if let failure { throw failure }
            return snapshot
        }
    }

    func writePlan(_ plan: PlanDocument) throws {
        try lock.withLock {
            if let failure { throw failure }
            self.plan = plan
        }
    }

    func readProfileUpdate() throws -> ProfileUpdate? {
        try lock.withLock {
            if let failure { throw failure }
            return profileUpdate
        }
    }

    func writeProfileUpdate(_ update: ProfileUpdate) throws {
        try lock.withLock {
            if let failure { throw failure }
            self.profileUpdate = update
        }
    }
}

// MARK: - Fixtures

/// A fixed instant on a second boundary, so ISO 8601 encoding round-trips it
/// exactly and whole-value equality is a fair assertion.
private let instant = Date(timeIntervalSince1970: 1_700_000_000)

private func makeSnapshot(catalogVersion: Int = 5) -> TrainingSnapshot {
    TrainingSnapshot(
        exportedAt: instant,
        catalogVersion: catalogVersion,
        performances: [
            SnapshotPerformance(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                occurredAt: instant, blockOrdinal: 1, sessionOrdinal: 1,
                sets: [SnapshotPerformedSet(
                    setIndex: 0, load: Mass(value: 225, unit: .pounds), reps: 5,
                    completedAt: instant)])
        ]
    )
}

private func makePlan(id: UUID = UUID(), focus: String = "Push") -> PlanDocument {
    PlanDocument(
        id: id, catalogVersion: 5, generatedAt: instant,
        sessions: [
            PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: focus,
                entries: [
                    .exercise(PlanDocumentExercise(
                        exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                        displayName: "Barbell Bench Press", restSeconds: 180,
                        coachNote: "Pause the last rep. Three down, explode up.",
                        sets: [
                            PlanDocumentSet(
                                target: .repetitions(low: 5, high: nil),
                                load: Mass(value: 225, unit: .pounds))
                        ]))
                ])
        ]
    )
}

private func makeProfileUpdate(id: UUID = UUID()) -> ProfileUpdate {
    ProfileUpdate(
        id: id, generatedAt: instant, experience: .stated(.advanced),
        equipment: .stated([.dumbbell, .plate]), goal: .stated("Bigger bench"),
        constraints: .unstated,
        preferredDurationMinutes: .stated(45)
    )
}

/// A directory that exists, cleaned up by the caller's `defer`.
private func makeTemporaryDirectory() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Document folder")
struct DocumentFolderTests {

    // MARK: - Both documents survive the trip

    @Test("A snapshot written to the folder reads back exactly as written")
    func snapshotRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)
        let snapshot = makeSnapshot()

        try folder.writeSnapshot(snapshot)

        #expect(try folder.readSnapshot() == snapshot)
    }

    @Test("A plan written to the folder reads back exactly as written")
    func planRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)
        let plan = makePlan()

        try folder.writePlan(plan)

        #expect(try folder.readPlan() == plan)
    }

    @Test("A profile update written to the folder reads back exactly as written")
    func profileUpdateRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)
        let update = makeProfileUpdate()

        try folder.writeProfileUpdate(update)

        #expect(try folder.readProfileUpdate() == update)
    }

    @Test("Every document has a fixed name, so neither side has to be told them")
    func filenamesAreFixed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        try folder.writeSnapshot(makeSnapshot())
        try folder.writePlan(makePlan())
        try folder.writeProfileUpdate(makeProfileUpdate())

        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        #expect(names == ["plan.json", "profile-update.json", "snapshot.json"])
    }

    @Test("Everything the server writes is something the app is told to watch for")
    func everyInboundDocumentIsWatchedFor() {
        // The watcher on the phone is driven by this list. A document written
        // into the folder but missing from it would sync and never be noticed.
        #expect(
            DocumentFolder.inboundFilenames.sorted()
                == [DocumentFolder.planFilename, DocumentFolder.profileUpdateFilename].sorted())
        #expect(!DocumentFolder.inboundFilenames.contains(DocumentFolder.snapshotFilename))
    }

    @Test("A later snapshot replaces the earlier one rather than being appended to it")
    func laterWriteReplacesEarlier() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        try folder.writeSnapshot(makeSnapshot(catalogVersion: 5))
        try folder.writeSnapshot(makeSnapshot(catalogVersion: 6))

        #expect(try folder.readSnapshot()?.catalogVersion == 6)
    }

    // MARK: - Absence is normal; broken is not

    @Test("A folder with no plan in it yet returns nil rather than throwing")
    func absentPlanIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try DocumentFolder(directory: directory).readPlan() == nil)
    }

    @Test("A folder with no snapshot in it yet returns nil rather than throwing")
    func absentSnapshotIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try DocumentFolder(directory: directory).readSnapshot() == nil)
    }

    @Test("A malformed plan throws rather than reading as no plan at all")
    func malformedPlanThrows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ this is not a plan".utf8)
            .write(to: directory.appending(path: DocumentFolder.planFilename))

        #expect(throws: (any Error).self) {
            try DocumentFolder(directory: directory).readPlan()
        }
    }

    @Test("A plan missing a required field throws rather than reading as no plan")
    func incompletePlanThrows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"version": 1, "title": "No identity"}"#.utf8)
            .write(to: directory.appending(path: DocumentFolder.planFilename))

        #expect(throws: (any Error).self) {
            try DocumentFolder(directory: directory).readPlan()
        }
    }

    @Test("A folder with no profile update in it yet returns nil rather than throwing")
    func absentProfileUpdateIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try DocumentFolder(directory: directory).readProfileUpdate() == nil)
    }

    @Test("A malformed profile update throws rather than reading as no update at all")
    func malformedProfileUpdateThrows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ this is not an update".utf8)
            .write(to: directory.appending(path: DocumentFolder.profileUpdateFilename))

        #expect(throws: (any Error).self) {
            try DocumentFolder(directory: directory).readProfileUpdate()
        }
    }

    @Test("A malformed snapshot throws rather than reading as no snapshot")
    func malformedSnapshotThrows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8)
            .write(to: directory.appending(path: DocumentFolder.snapshotFilename))

        #expect(throws: (any Error).self) {
            try DocumentFolder(directory: directory).readSnapshot()
        }
    }

    // MARK: - A folder that is not there

    @Test("Writing into a folder that does not exist throws rather than failing silently")
    func writingIntoMissingFolderThrows() {
        let folder = DocumentFolder(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString)
        )

        #expect(throws: (any Error).self) { try folder.writeSnapshot(makeSnapshot()) }
    }

    @Test("Reading from a folder that does not exist reads as nothing there yet")
    func readingFromMissingFolderIsNil() throws {
        let folder = DocumentFolder(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString)
        )

        #expect(try folder.readPlan() == nil)
    }
}

@Suite("In-memory transport")
struct InMemoryDocumentTransportTests {

    @Test("The fake round-trips every document, so a caller can be tested without a disk")
    func fakeRoundTripsEveryDocument() throws {
        let transport = InMemoryDocumentTransport()
        let snapshot = makeSnapshot()
        let plan = makePlan()
        let update = makeProfileUpdate()

        try transport.writeSnapshot(snapshot)
        try transport.writePlan(plan)
        try transport.writeProfileUpdate(update)

        #expect(try transport.readSnapshot() == snapshot)
        #expect(try transport.readPlan() == plan)
        #expect(try transport.readProfileUpdate() == update)
    }

    @Test("The fake reports an empty transport as nil, the same as a folder does")
    func fakeReportsAbsenceAsNil() throws {
        #expect(try InMemoryDocumentTransport().readPlan() == nil)
    }

    @Test("A broken transport throws on read rather than looking like no plan")
    func brokenFakeThrowsOnRead() {
        let transport = InMemoryDocumentTransport(plan: makePlan())
        transport.breakTransport()

        #expect(throws: (any Error).self) { try transport.readPlan() }
    }

    @Test("A broken transport throws on write rather than silently dropping the snapshot")
    func brokenFakeThrowsOnWrite() {
        let transport = InMemoryDocumentTransport()
        transport.breakTransport()

        #expect(throws: (any Error).self) { try transport.writeSnapshot(makeSnapshot()) }
    }

    @Test("Anything holding the protocol can be handed the fake in place of a folder")
    func fakeSatisfiesTheSeam() throws {
        let transport: any DocumentTransport = InMemoryDocumentTransport(plan: makePlan())

        try transport.writeSnapshot(makeSnapshot())

        #expect(try transport.readPlan()?.sessions.first?.focus == "Push")
    }

    /// A key that has been retired reads rather than refusing the document
    /// whole. An update written before the fact went is not a broken update,
    /// and refusing it would lose everything else it said.
    @Test("An update naming a retired fact still reads, and the fact is ignored")
    func aRetiredKeyDoesNotRefuseTheDocument() throws {
        let data = Data("""
            {"version": 3, "id": "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1",
             "generatedAt": "2023-11-14T22:13:20Z",
             "goal": "Bench 225", "preferredWeekdays": ["monday", "thursday"]}
            """.utf8)

        let update = try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: data)

        #expect(update.goal == .stated("Bench 225"), "everything else it said survives")
    }
}
