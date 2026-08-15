import Foundation
import OSLog
import LiftingKit

/// Announces a `plan.json` arriving in the app's iCloud Documents folder.
///
/// Hand one to `PlanInbox`, which starts it; it does the rest. A file syncing
/// in from another device does not reliably fire ordinary filesystem events, so
/// this uses `NSMetadataQuery` over the ubiquitous documents scope — the same
/// mechanism the Files app uses to notice a document appear.
///
/// **A file that is announced is not necessarily a file that is here.** iCloud
/// advertises an item before its contents have been fetched, so this asks for
/// the download and announces only once the item reports itself current. A
/// caller reading a placeholder would see an error where the honest answer is
/// "not yet".
///
/// Depends on: `NSMetadataQuery`, `FileManager`'s ubiquity downloads, and
/// `DocumentFolder`'s file name from `LiftingKit`. Main-actor bound because
/// `NSMetadataQuery` delivers on the main run loop.
@MainActor
final class UbiquitousPlanWatcher: PlanArrivalWatching {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LiftingPlan", category: "plan-watch"
    )

    private let query = NSMetadataQuery()
    private var observers: [any NSObjectProtocol] = []
    private var onArrival: (() -> Void)?

    func start(onArrival: @escaping () -> Void) {
        guard !query.isStarted else { return }
        self.onArrival = onArrival

        // Scoped to the one file name both sides agreed on, so an unrelated
        // document in the container never wakes the importer.
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemFSNameKey, DocumentFolder.planFilename
        )
        // The first gather reports what is already there, which is how a plan
        // that arrived while the app was closed gets imported at launch.
        observe(.NSMetadataQueryDidFinishGathering)
        observe(.NSMetadataQueryDidUpdate)
        query.start()
    }

    func stop() {
        query.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        onArrival = nil
    }

    private func observe(_ name: Notification.Name) {
        let observer = NotificationCenter.default.addObserver(
            forName: name, object: query, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue by the queue argument above, so the
            // main actor's isolation is already satisfied.
            MainActor.assumeIsolated { self?.handleResults() }
        }
        observers.append(observer)
    }

    /// Announces an arrival if the plan is downloaded, and asks for it if it is
    /// not.
    ///
    /// Updates are paused while the results are read, because the query mutates
    /// them on the main run loop and a caller walking them meanwhile would see
    /// a moving target.
    private func handleResults() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var isReadyToImport = false
        for item in query.results.compactMap({ $0 as? NSMetadataItem }) {
            if isDownloaded(item) {
                isReadyToImport = true
            } else {
                requestDownload(of: item)
            }
        }
        if isReadyToImport {
            onArrival?()
        }
    }

    private func isDownloaded(_ item: NSMetadataItem) -> Bool {
        let status = item.value(
            forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
        ) as? String
        return status == NSMetadataUbiquitousItemDownloadingStatusCurrent
    }

    /// Asks iCloud for the contents of an item it has only advertised.
    ///
    /// The failure is logged rather than propagated because there is no caller
    /// to propagate to and nothing for the lifter to do: iCloud retries, and
    /// the query announces again when the contents land. Nothing is lost — the
    /// plan stays in the folder until it can be read.
    private func requestDownload(of item: NSMetadataItem) {
        guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            Self.logger.error(
                "Could not start downloading the plan: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
