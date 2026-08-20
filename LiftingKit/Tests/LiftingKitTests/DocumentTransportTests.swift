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
        catalogVersion: catalogVersion,
        generatedAt: instant,
        profile: SnapshotProfile(
            displayUnit: .pounds, experience: .intermediate,
            availableEquipment: [EquipmentType(rawValue: "barbell")],
            goal: "Bigger bench", constraints: "Left shoulder is touchy",
            bodyweight: Mass(value: 182, unit: .pounds),
            avoidedPatterns: [], avoidedExercises: [],
            preferredWeekdays: [.monday, .thursday],
            preferredDurationMinutes: 60, statedAt: ["goal": Date(timeIntervalSince1970: 1_700_000_000)]
        ),
        baselines: [
            SnapshotBaseline(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                load: Mass(value: 225, unit: .pounds), reps: 5, recordedAt: instant
            )
        ]
    )
}

private func makePlan(id: UUID = UUID(), title: String = "Strength block") -> PlanDocument {
    PlanDocument(
        id: id, catalogVersion: 5, generatedAt: instant, title: title,
        goal: "Bigger bench", durationMinutes: 60,
        notes: "Keep pressing volume moderate.",
        days: [
            PlanDocumentDay(
                weekday: .monday, focus: "Push", durationMinutes: 60,
                exercises: [
                    PlanDocumentExercise(
                        exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                        displayName: "Barbell Bench Press", sets: 3, repRange: "5",
                        restSeconds: 180, suggestedLoad: Mass(value: 225, unit: .pounds),
                        tempo: "3-0-1-0", notes: "Pause the last rep"
                    )
                ]
            )
        ]
    )
}

private func makeProfileUpdate(id: UUID = UUID()) -> ProfileUpdate {
    ProfileUpdate(
        id: id, generatedAt: instant, experience: .stated(.advanced),
        equipment: .stated([.dumbbell, .plate]), goal: .stated("Bigger bench"),
        constraints: .unstated, preferredWeekdays: .stated([.monday, .thursday]),
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

        #expect(try transport.readPlan()?.title == "Strength block")
    }
}
