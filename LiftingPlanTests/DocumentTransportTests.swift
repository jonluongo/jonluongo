import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The app's half of the transport: resolving the shared iCloud folder, and
/// what happens when there isn't one.
///
/// The folder semantics themselves — absence versus corruption, atomic writes,
/// fixed file names — are `DocumentFolder`'s and are covered in the package
/// suite. What is tested here is the resolution step the phone adds, because
/// that is the step that can fail on a real device.
@Suite("iCloud document transport")
struct ICloudDocumentTransportTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot() -> TrainingSnapshot {
        TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant)
    }

    private func plan(id: UUID = UUID()) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: Self.instant, title: "Strength block"
        )
    }

    /// A stand-in for a signed-in device: a real folder the resolver hands back
    /// in place of the ubiquity container.
    private func temporaryContainer() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func transport(container: URL?) -> ICloudDocumentTransport {
        ICloudDocumentTransport(
            containerIdentifier: "iCloud.com.jonluongo.LiftingPlan",
            resolveContainer: { _ in container }
        )
    }

    // MARK: - A container that is not there

    @Test("Writing with no iCloud container throws rather than writing into nowhere")
    func writeWithoutContainerThrows() {
        #expect(throws: ICloudTransportError.self) {
            try transport(container: nil).writeSnapshot(snapshot())
        }
    }

    @Test("Reading with no iCloud container throws rather than reporting no plan")
    func readWithoutContainerThrows() {
        // The distinction that matters: an unavailable container must not
        // return nil, because nil means "the coach has not sent a plan yet".
        #expect(throws: ICloudTransportError.self) {
            try transport(container: nil).readPlan()
        }
    }

    @Test("The failure names the container, so the cause is fixable rather than mysterious")
    func failureNamesTheContainer() throws {
        let error = ICloudTransportError.containerUnavailable("iCloud.com.jonluongo.LiftingPlan")

        let description = try #require(error.errorDescription)
        #expect(description.contains("iCloud.com.jonluongo.LiftingPlan"))
    }

    // MARK: - A container that is there

    @Test("A snapshot is written into the container's Documents folder, where the Mac looks")
    func writesIntoDocumentsFolder() throws {
        let container = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        try transport(container: container).writeSnapshot(snapshot())

        let file = container
            .appending(path: "Documents")
            .appending(path: DocumentFolder.snapshotFilename)
        #expect(try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: Data(contentsOf: file)) == snapshot())
    }

    @Test("A plan left in the container's Documents folder is read back")
    func readsPlanFromDocumentsFolder() throws {
        let container = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let documents = container.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let written = plan()
        try DocumentFolder(directory: documents).writePlan(written)

        #expect(try transport(container: container).readPlan() == written)
    }

    @Test("A container with nothing in it yet reports no plan rather than failing")
    func emptyContainerHasNoPlan() throws {
        let container = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(try transport(container: container).readPlan() == nil)
    }

    @Test("A profile update left in the container's Documents folder is read back")
    func readsProfileUpdateFromDocumentsFolder() throws {
        let container = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let documents = container.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let written = ProfileUpdate(
            id: UUID(), generatedAt: Self.instant, equipmentAccess: .stated(.fullGym))
        try DocumentFolder(directory: documents).writeProfileUpdate(written)

        #expect(try transport(container: container).readProfileUpdate() == written)
    }

    @Test("Reading a profile update with no iCloud container throws rather than reporting none")
    func readProfileUpdateWithoutContainerThrows() {
        // Same distinction as the plan: an unavailable container must not
        // return nil, because nil means "nothing has been recorded yet".
        #expect(throws: ICloudTransportError.self) {
            try transport(container: nil).readProfileUpdate()
        }
    }

    @Test("A malformed plan in the container throws rather than reading as no plan")
    func malformedPlanInContainerThrows() throws {
        let container = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let documents = container.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("{ not a plan".utf8)
            .write(to: documents.appending(path: DocumentFolder.planFilename))

        #expect(throws: (any Error).self) { try transport(container: container).readPlan() }
    }
}
