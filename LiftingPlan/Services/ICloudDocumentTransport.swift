import Foundation
import LiftingKit

/// Why the shared iCloud folder could not be reached.
///
/// Catch it where the loop is driven and show `errorDescription` — it names the
/// container, which is what makes "iCloud is signed out" distinguishable from
/// "the entitlement is wrong". It is deliberately not silent and deliberately
/// not `nil`: an unreachable container must never read as "no plan yet".
///
/// Depends on: Foundation only.
enum ICloudTransportError: Error, LocalizedError, Equatable {

    /// The ubiquity container could not be resolved. The associated value is
    /// the container identifier that was asked for.
    case containerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .containerUnavailable(let identifier):
            "Can't reach the iCloud folder '\(identifier)'. Check that iCloud "
                + "Drive is on and this device is signed in."
        }
    }
}

/// The loop's transport on the phone: the app's iCloud Documents folder.
///
/// Build one and hand it to whatever drives the loop — `LiftingPlanApp` writes
/// the snapshot through it when the app backgrounds, and `PlanInbox` reads
/// plans through it. Both machines are signed into the same Apple ID, so the
/// Mac writing into the same container is all the syncing this needs; there is
/// no server and no account to manage.
///
/// The container is resolved on every call rather than once at launch, because
/// iCloud can become available after the app has started — a lifter who signs
/// in should not have to relaunch. Resolution that fails throws
/// `ICloudTransportError.containerUnavailable`; it never falls back to a local
/// folder, which would look like a working export while the Mac saw nothing.
///
/// Resolving asks the system for the container, which can block, so this is
/// called on scene transitions and file-arrival events — never from a view
/// update.
///
/// Depends on: `DocumentTransport` and `DocumentFolder` from `LiftingKit`, and
/// `FileManager`'s ubiquity container lookup.
struct ICloudDocumentTransport: DocumentTransport {

    /// The container in `LiftingPlan.entitlements`. The same one CloudKit
    /// mirrors the store into — one container, two scopes.
    static let defaultContainerIdentifier = "iCloud.com.jonluongo.LiftingPlan"

    /// The subfolder of a ubiquity container that iCloud syncs as documents.
    /// Fixed by the system, not a choice.
    static let documentsFolderName = "Documents"

    private let containerIdentifier: String
    private let resolveContainer: @Sendable (String) -> URL?

    /// - Parameters:
    ///   - containerIdentifier: the ubiquity container to use. Defaults to the
    ///     app's own.
    ///   - resolveContainer: how a container identifier becomes a folder.
    ///     Defaults to the system lookup; a test supplies a real directory, or
    ///     `nil` to stand in for a device that is not signed in.
    init(
        containerIdentifier: String = ICloudDocumentTransport.defaultContainerIdentifier,
        resolveContainer: @escaping @Sendable (String) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) {
        self.containerIdentifier = containerIdentifier
        self.resolveContainer = resolveContainer
    }

    func writeSnapshot(_ snapshot: TrainingSnapshot) throws {
        let folder = try documentsFolder()
        // Created on write only. A container whose Documents folder does not
        // exist yet holds no plan, so reading must not conjure one.
        try FileManager.default.createDirectory(
            at: folder.url, withIntermediateDirectories: true
        )
        try folder.writeSnapshot(snapshot)
    }

    func readPlan() throws -> PlanDocument? {
        try documentsFolder().readPlan()
    }

    /// The shared folder inside the container, for a caller that has to watch
    /// it. Throws when there is no container to look in.
    func documentsFolder() throws -> DocumentFolder {
        guard let container = resolveContainer(containerIdentifier) else {
            throw ICloudTransportError.containerUnavailable(containerIdentifier)
        }
        return DocumentFolder(directory: container.appending(path: Self.documentsFolderName))
    }
}
