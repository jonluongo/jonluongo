import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

@MainActor
@Suite("Snapshot outbox")
struct SnapshotOutboxTests {

    // MARK: - Fixtures

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func temporaryFolder() throws -> DocumentFolder {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DocumentFolder(directory: url)
    }

    private func outbox(
        transport: any DocumentTransport, context: ModelContext
    ) throws -> SnapshotOutbox {
        SnapshotOutbox(transport: transport, context: context, catalog: try catalog())
    }

    // MARK: - A snapshot that goes out

    @Test("Exporting writes a snapshot the other side can read back")
    func exportWritesAReadableSnapshot() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let outbox = try outbox(transport: folder, context: context)

        await outbox.exportSnapshot()

        #expect(try folder.readSnapshot() != nil)
        #expect(outbox.errorMessage == nil)
    }

    // MARK: - A snapshot that does not, and says so

    @Test("A transport that cannot reach its container reports it rather than failing silently")
    func unreachableContainerIsShownToTheLifter() async throws {
        // Exactly the state of a phone with iCloud Drive turned off, which is
        // the failure that otherwise breaks the outbound half forever with no
        // sign of it anywhere the lifter looks.
        let transport = ICloudDocumentTransport(
            containerIdentifier: ICloudDocumentTransport.defaultContainerIdentifier,
            resolveContainer: { _ in nil }
        )
        let outbox = try outbox(transport: transport, context: try context())

        await outbox.exportSnapshot()

        let message = try #require(outbox.errorMessage)
        #expect(message.contains(ICloudDocumentTransport.defaultContainerIdentifier))
    }

    @Test("A later export that works clears the earlier failure")
    func successClearsAnEarlierFailure() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let context = try context()
        let failing = try outbox(
            transport: ICloudDocumentTransport(resolveContainer: { _ in nil }), context: context
        )
        await failing.exportSnapshot()
        #expect(failing.errorMessage != nil)

        let working = try outbox(transport: folder, context: context)
        await working.exportSnapshot()

        #expect(working.errorMessage == nil)
    }

    @Test("Dismissing the failure clears it, so it is not shown twice")
    func dismissingClearsTheFailure() async throws {
        let outbox = try outbox(
            transport: ICloudDocumentTransport(resolveContainer: { _ in nil }),
            context: try context()
        )

        await outbox.exportSnapshot()
        outbox.dismissError()

        #expect(outbox.errorMessage == nil)
    }

    // MARK: - Written is not delivered

    /// A transport that writes into a real folder, and answers as iCloud would
    /// about whether the file ever left the phone.
    private func iCloudTransport(
        at directory: URL, uploadFailure: String?
    ) -> ICloudDocumentTransport {
        ICloudDocumentTransport(
            containerIdentifier: "iCloud.test",
            resolveContainer: { _ in directory },
            uploadFailure: { _ in uploadFailure }
        )
    }

    @Test("A snapshot iCloud will not take is reported, not counted as sent")
    func anUndeliveredSnapshotIsReported() async throws {
        // The failure this closes broke the product silently: the write into
        // the ubiquity container is local and succeeds, iCloud refuses to
        // carry it — a full account is the ordinary case — and nothing threw.
        // The app looked fine while the coach read nothing.
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try context()
        let outbox = try outbox(
            transport: iCloudTransport(at: directory, uploadFailure: "Quota exceeded"),
            context: context)

        await outbox.exportSnapshot()

        let message = try #require(outbox.errorMessage)
        #expect(message.contains("Quota exceeded"), "iCloud's own reason, not a paraphrase")
        #expect(message.contains("coach"), "what it costs him is the point of saying it")
        // The file is still written: the record is the phone's either way, and
        // it goes out the moment iCloud will take it.
        #expect(try DocumentFolder(
            directory: directory.appending(path: "Documents")).readSnapshot() != nil)
    }

    @Test("A snapshot iCloud takes is reported as nothing at all")
    func aDeliveredSnapshotSaysNothing() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try context()
        let outbox = try outbox(
            transport: iCloudTransport(at: directory, uploadFailure: nil), context: context)

        await outbox.exportSnapshot()

        #expect(outbox.errorMessage == nil)
    }

    // MARK: - The same failure, every launch

    @Test("A failure he has closed is not raised again by the next export")
    func aDismissedFailureStaysDismissed() async throws {
        // A full iCloud account does not fix itself between sessions, so every
        // export says the same thing. Meeting him with it at every launch is
        // the alert nagging rather than informing.
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try context()
        let outbox = try outbox(
            transport: iCloudTransport(at: directory, uploadFailure: "Quota exceeded"),
            context: context)

        await outbox.exportSnapshot()
        #expect(outbox.errorMessage != nil, "the first one has to reach him")
        outbox.dismissError()
        await outbox.exportSnapshot()

        #expect(outbox.errorMessage == nil, "the same sentence, already read and closed")
    }

    @Test("A different failure after that one is still heard")
    func aNewFailureIsRaised() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let iCloud = UploadState("Quota exceeded")
        let outbox = try outbox(
            transport: iCloudTransport(at: directory, state: iCloud), context: try context())

        await outbox.exportSnapshot()
        outbox.dismissError()
        // The account has room now, and the phone is signed out instead.
        iCloud.failure = "Not signed in"
        await outbox.exportSnapshot()

        #expect(try #require(outbox.errorMessage).contains("Not signed in"))
    }

    @Test("An export that goes through forgets the dismissal")
    func aGoodExportForgetsIt() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let iCloud = UploadState("Quota exceeded")
        let outbox = try outbox(
            transport: iCloudTransport(at: directory, state: iCloud), context: try context())

        await outbox.exportSnapshot()
        outbox.dismissError()
        iCloud.failure = nil
        await outbox.exportSnapshot()
        #expect(outbox.errorMessage == nil)

        // The same failure again, after a clean one: nothing is suppressed for
        // the life of the process.
        iCloud.failure = "Quota exceeded"
        await outbox.exportSnapshot()

        #expect(outbox.errorMessage != nil)
    }

    /// What iCloud is saying about the file this time, changeable between
    /// exports so one outbox can live through a failure, a fix and a relapse.
    private final class UploadState: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?

        init(_ failure: String?) { stored = failure }

        var failure: String? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private func iCloudTransport(at directory: URL, state: UploadState)
        -> ICloudDocumentTransport
    {
        ICloudDocumentTransport(
            containerIdentifier: "iCloud.test",
            resolveContainer: { _ in directory },
            uploadFailure: { _ in state.failure }
        )
    }

    // MARK: - The real answer, on files iCloud knows nothing about

    @Test("A file iCloud has no opinion about is not reported as a failure")
    func aPlainFileIsNotAFailure() throws {
        // The check reads `ubiquitousItemUploadingError` off the file. On a
        // plain folder — a simulator, a test, a server pointed somewhere with
        // `--documents` — the key is simply absent, and reading absence as a
        // failure would put "iCloud has not taken it" in front of a lifter
        // whose record is exactly where it belongs.
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ICloudDocumentTransport.systemUploadFailure(for: url) == nil)
    }

    @Test("A file that is not there is not reported as a failure either")
    func aMissingFileIsNotAFailure() {
        // Asked before the first export has written anything.
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")

        #expect(ICloudDocumentTransport.systemUploadFailure(for: url) == nil)
    }
}
