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
    private var notes: [NoteFile: String] = [:]
    private var failure: (any Error)?

    struct Broken: Error {}

    init(
        snapshot: TrainingSnapshot? = nil, plan: PlanDocument? = nil,
        notes: [NoteFile: String] = [:]
    ) {
        self.snapshot = snapshot
        self.plan = plan
        self.notes = notes
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

    func readNote(_ note: NoteFile) throws -> String? { notes[note] }

    func writeNote(_ text: String, as note: NoteFile) throws { notes[note] = text }

    /// Keeps the first copy of each plan and never replaces it, which is the
    /// behaviour the folder promises and the thing a caller can get wrong.
    private(set) var archived: [UUID: PlanDocument] = [:]

    func archivePlan(_ plan: PlanDocument) throws {
        try lock.withLock {
            if let failure { throw failure }
            if archived[plan.id] == nil { archived[plan.id] = plan }
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
            SnapshotPerformedExercise(
                exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
                occurredAt: instant, blockOrdinal: 1, sessionOrdinal: 1,
                sets: [SnapshotPerformedSet(
                    setIndex: 0, load: Mass(value: 225, unit: .pounds), work: .repetitions(5), completedAt: instant)])
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

    @Test("A note the coach wrote reads back as the text he wrote")
    func aNoteRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        let folder = DocumentFolder(directory: directory)
        let written = """
            # The user

            ## Objective
            D1 offensive line.
            """

        try folder.writeNote(written, as: .account)

        #expect(try folder.readNote(.account) == written)
        #expect(try folder.readNote(.program) == nil, "he has written no programme note")
    }

    @Test("Every document has a fixed name, so neither side has to be told them")
    func filenamesAreFixed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = DocumentFolder(directory: directory)

        try folder.writeSnapshot(makeSnapshot())
        try folder.writePlan(makePlan())
        try folder.writeNote("# The user", as: .account)
        try folder.writeNote("# This programme", as: .program)

        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        #expect(names == ["ACCOUNT.md", "PROGRAM.md", "plan.json", "snapshot.json"])
    }

    @Test("Everything the server writes is something the app is told to watch for")
    func everyInboundDocumentIsWatchedFor() {
        // The watcher on the phone is driven by this list. A document written
        // into the folder but missing from it would sync and never be noticed.
        #expect(
            DocumentFolder.inboundFilenames.sorted()
                == ([DocumentFolder.planFilename] + NoteFile.allCases.map(\.filename)).sorted())
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

    @Test("A folder with no note in it yet returns nil rather than throwing")
    func absentNoteIsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try DocumentFolder(directory: directory).readNote(.account) == nil)
        #expect(try DocumentFolder(directory: directory).readNote(.program) == nil)
    }

    @Test("A note is text, so there is nothing in it that can be malformed")
    func aNoteCannotBeMalformed() throws {
        // **This is what makes prose different from a document.** A malformed
        // plan throws, because half a prescription is worse than none. A note
        // has no shape to violate — whatever the coach wrote is what he wrote,
        // and the app renders it. The guard against losing his words is at the
        // other end: `update_notes` is an anchored edit, refused when the text
        // it expects to replace is not there.
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ this is not markdown, and that is fine".utf8)
            .write(to: directory.appending(path: NoteFile.account.filename))

        #expect(
            try DocumentFolder(directory: directory).readNote(.account)
                == "{ this is not markdown, and that is fine")
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

        try transport.writeSnapshot(snapshot)
        try transport.writePlan(plan)
        try transport.writeNote("# The user", as: .account)

        #expect(try transport.readSnapshot() == snapshot)
        #expect(try transport.readPlan() == plan)
        #expect(try transport.readNote(.account) == "# The user")
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

}

/// What happens to a plan after it has been taken in.
///
/// **The defect this closes.** `Session.sourceDocumentID` was stored, exported
/// and reconstructed while pointing at nothing: `plan.json` is replaced by the
/// next plan the coach writes, so the document a session named had ceased to
/// exist anywhere. `CLAUDE.md` and `docs/decided.md` both described the archive
/// that fixes it; nothing wrote it.
@Suite("The plan archive")
struct PlanArchiveTests {

    private func folder() throws -> (DocumentFolder, URL) {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (DocumentFolder(directory: directory), directory)
    }

    @Test("A kept plan is readable back as the document it was")
    func aKeptPlanReadsBack() throws {
        let (subject, _) = try folder()
        let plan = makePlan(focus: "Pull")

        try subject.archivePlan(plan)

        let kept = try #require(try subject.archivedPlans().first)
        #expect(kept.id == plan.id)
        #expect(kept.sessions.first?.focus == "Pull")
    }

    @Test("It is named by the document's own ID, which is what a session records")
    func theFileIsNamedByTheID() throws {
        let (subject, directory) = try folder()
        let plan = makePlan()

        try subject.archivePlan(plan)

        let file = directory
            .appending(path: DocumentFolder.planArchiveFolder)
            .appending(path: "\(plan.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test("Keeping the same plan twice keeps the first copy and does not throw")
    func theFirstCopyIsTheOneKept() throws {
        // The folder is announced whenever anything in it changes, including
        // the snapshot this app writes, so a plan is re-read many times. A
        // prescription already taken in is permanent for the same reason a
        // trained one is.
        let (subject, _) = try folder()
        let id = UUID()

        try subject.archivePlan(makePlan(id: id, focus: "Push"))
        try subject.archivePlan(makePlan(id: id, focus: "Rewritten"))

        let kept = try subject.archivedPlans()
        #expect(kept.count == 1)
        #expect(kept.first?.sessions.first?.focus == "Push")
    }

    @Test("Two plans are two files")
    func everyPlanIsKept() throws {
        let (subject, _) = try folder()
        try subject.archivePlan(makePlan(focus: "Push"))
        try subject.archivePlan(makePlan(focus: "Pull"))

        #expect(try subject.archivedPlans().count == 2)
    }

    @Test("A folder with no archive yet reports none rather than failing")
    func absenceIsNotFailure() throws {
        // Exactly the state of a user who has never been sent a plan, which
        // must not look like a broken transport.
        let (subject, _) = try folder()
        #expect(try subject.archivedPlans().isEmpty)
    }

    // MARK: - The version kept before an edit

    @Test("The version kept before an edit goes in the versions folder, not the root")
    func aKeptNoteIsNotLooseInTheRoot() throws {
        // **The container root is what a person reads to see what the loop is
        // doing** — four names, both machines looking for them. One copy per
        // edit accumulates there without bound, for files nothing reads back.
        // Untested, this had drifted from the format the project documents.
        let (subject, directory) = try folder()
        try subject.writeNote("# Account\n\n## Recovery\n- Sleeps six.\n", as: .account)

        try subject.keepCopy(of: "# Account\n\n## Recovery\n- Sleeps six.\n", as: .account)

        let root = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(root.contains(NoteFile.account.filename), "the live note stays where it is")
        #expect(root.filter { $0.hasSuffix(".md") } == [NoteFile.account.filename],
                "and it is the only markdown loose in the root: \(root)")

        let kept = try FileManager.default.contentsOfDirectory(
            atPath: directory.appending(path: DocumentFolder.noteVersionFolder).path)
        #expect(kept.count == 1)
        #expect(kept.allSatisfy { $0.hasPrefix(NoteFile.account.basename) })
    }

    @Test("Two edits keep two versions rather than overwriting one backup")
    func everyVersionIsKept() throws {
        // **The same note, twice, as fast as the machine goes.** A coach fixing
        // two sections makes two tool calls back to back; at second precision
        // the second copy landed on the first's name and the intermediate
        // version was gone — one backup that keeps being overwritten, which is
        // what keeping a *dated* copy exists to avoid.
        let (subject, directory) = try folder()
        try subject.keepCopy(of: "first", as: .account)
        try subject.keepCopy(of: "second", as: .account)

        let kept = try FileManager.default.contentsOfDirectory(
            atPath: directory.appending(path: DocumentFolder.noteVersionFolder).path)
        #expect(kept.count == 2, "\(kept)")
    }

    @Test("Keeping a copy does not disturb the note being read")
    func theLiveNoteIsUntouched() throws {
        let (subject, _) = try folder()
        try subject.writeNote("live", as: .account)

        try subject.keepCopy(of: "live", as: .account)

        #expect(try subject.readNote(.account) == "live")
    }

    @Test("Archiving does not disturb the plan waiting to be read")
    func theLivePlanIsUntouched() throws {
        let (subject, _) = try folder()
        let plan = makePlan(focus: "Push")
        try subject.writePlan(plan)

        try subject.archivePlan(plan)

        #expect(try subject.readPlan()?.id == plan.id, "plan.json is still the live document")
        #expect(try subject.archivedPlans().count == 1)
    }
}
