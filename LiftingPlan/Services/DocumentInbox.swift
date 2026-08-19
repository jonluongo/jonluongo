import Foundation
import SwiftData
import LiftingKit

/// Tells its caller that something Claude wrote has turned up in the shared
/// folder.
///
/// Conform to it to announce arrivals however a platform announces them —
/// `UbiquitousDocumentWatcher` uses `NSMetadataQuery`, because a file arriving
/// from iCloud does not reliably fire ordinary filesystem events — and conform a
/// fake to it in tests to announce one on demand. It carries no document and
/// does not say which file moved: what arrived is the transport's business, not
/// the watcher's, and the inbox reads whatever is waiting either way.
///
/// Depends on: nothing. Deliberately: this is the seam that keeps
/// `DocumentInbox` free of iCloud.
@MainActor
protocol DocumentArrivalWatching: AnyObject {

    /// Begins watching. `onArrival` is called once per announcement, on the
    /// main actor. Calling it again while already watching does nothing.
    ///
    /// It is `async` because handling an arrival has to leave the main actor —
    /// reading the document resolves the iCloud container — and a watcher that
    /// could only call back synchronously would force that work back onto the
    /// thread it must not run on.
    func start(onArrival: @escaping @MainActor () async -> Void)

    /// Stops watching and releases whatever the watch was holding.
    func stop()
}

/// Takes in everything Claude sends the moment it arrives, so the lifter never
/// hunts for a refresh button.
///
/// Build one with the app's transport, a watcher, the `ModelContext`, and the
/// loaded catalog; call `start()` once and read `errorMessage` to show what went
/// wrong. It is the only caller of `PlanImporter` and `ProfileUpdater`, which
/// makes this the whole of the app's inbound half of the loop: Claude writes on
/// the Mac, iCloud carries it, this notices and applies it.
///
/// **Two documents, one path.** A plan says what to train; a profile update says
/// what has been learned about the lifter, which matters because the app asks
/// him nothing. They arrive the same way and are read together on every
/// announcement, so a folder holding both settles in one pass rather than
/// needing two.
///
/// **Absence and corruption are told apart.** A transport with nothing in it is
/// the ordinary state of a lifter at the start, and passes in silence. A
/// document that is there but unreadable — malformed, or naming an exercise the
/// catalog does not have — sets `errorMessage` and changes nothing, because a
/// corrupt document that read as an empty one would leave the lifter staring at
/// an empty screen with no idea why.
///
/// Re-reading is safe: both documents carry a stable identity and both are
/// applied once, so they are left in place rather than consumed. Re-applying
/// an identity already applied changes nothing and announces nothing, so a
/// folder announcing itself repeatedly does not write the snapshot repeatedly.
///
/// Depends on: `DocumentTransport` and `ExerciseCatalogProviding` from
/// `LiftingKit`, `DocumentArrivalWatching`, `PlanImporter`, `ProfileUpdater`,
/// and the store's `ModelContext`.
@MainActor
@Observable
final class DocumentInbox {

    /// What went wrong the last time the folder was read, ready to show. `nil`
    /// when nothing has gone wrong — which includes there being nothing there.
    private(set) var errorMessage: String?

    /// Called after a document has actually been applied — never when the
    /// folder was empty, and never when everything in it was refused.
    ///
    /// **It exists so the snapshot cannot be older than the plan it describes.**
    /// The record changes the moment Claude's plan lands, and until this the
    /// only thing that wrote the snapshot back out was the app being
    /// backgrounded. A lifter who received a block, trained it, and never left
    /// the app left the coach reading a document written before the block
    /// existed — which is the shape of the report that the snapshot held four
    /// sessions when the block prescribed nine.
    ///
    /// **Announced is not applied, and the difference is load-bearing.** The
    /// snapshot is written into the same folder this watches, so an export
    /// announces the folder, which reads it again. If a document that was
    /// merely re-announced counted as an arrival, that would export again, and
    /// the two halves would write to each other forever. Both importers are
    /// asked whether the identity is already in the store *before* applying,
    /// which is the same question they answer internally.
    ///
    /// The inbox does not know what an outbox is: the composition root wires
    /// this, so neither half of the loop depends on the other.
    var onApplied: (@MainActor () async -> Void)?

    private let transport: any DocumentTransport
    private let watcher: any DocumentArrivalWatching
    private let context: ModelContext
    private let catalog: any ExerciseCatalogProviding

    init(
        transport: any DocumentTransport,
        watcher: any DocumentArrivalWatching,
        context: ModelContext,
        catalog: any ExerciseCatalogProviding
    ) {
        self.transport = transport
        self.watcher = watcher
        self.context = context
        self.catalog = catalog
    }

    /// Starts watching for documents.
    ///
    /// No read happens here. The watcher announces what is already in the
    /// folder as its first event, so anything waiting at launch is taken in the
    /// same way as something that lands mid-session — and resolving the iCloud
    /// container, which can block, stays off the launch path.
    func start() {
        watcher.start { [weak self] in
            guard let self else { return }
            await self.importWaitingDocuments()
        }
    }

    /// Stops watching. The store keeps whatever was already applied.
    func stop() {
        watcher.stop()
    }

    /// Clears a reported failure, after the lifter has been shown it.
    func dismissError() {
        errorMessage = nil
    }

    /// Reads whatever is waiting and applies it.
    ///
    /// The failures are held rather than thrown because the caller is an
    /// arrival announcement with nowhere to return an error to. Nothing is
    /// discarded: `errorMessage` is what the UI puts in front of the lifter, and
    /// the documents stay in the folder, so a fixed one applies on its next
    /// announcement.
    ///
    /// The two documents are handled independently, so an unreadable plan does
    /// not stop a perfectly good profile update from landing — and both
    /// failures are reported rather than only the last. The profile goes first:
    /// it is the context a plan is read in.
    ///
    /// The reads happen off the main actor and the writes on it: resolving the
    /// iCloud container can block for seconds and must not run on the main
    /// thread, while `ModelContext` must. Both documents are pure value types,
    /// so they cross between them.
    func importWaitingDocuments() async {
        var failures: [String] = []
        var applied = false
        do {
            // Nothing waiting is the normal state, not something to report.
            if let update = try await Self.readProfileUpdate(from: transport) {
                let isNew = try !ProfileUpdater.isApplied(update, in: context)
                try ProfileUpdater.apply(update, to: context, catalog: catalog)
                applied = applied || isNew
            }
        } catch {
            failures.append(Self.describe(error))
        }
        do {
            if let document = try await Self.readPlan(from: transport) {
                let isNew = try !PlanImporter.isImported(document, in: context)
                try PlanImporter.import(document, into: context, catalog: catalog)
                applied = applied || isNew
            }
        } catch {
            failures.append(Self.describe(error))
        }
        // A transport that cannot be reached at all fails both reads with the
        // same sentence; saying it twice would read as two separate problems.
        errorMessage = Self.deduplicated(failures).joined(separator: "\n\n").nilWhenEmpty
        // After the failures are recorded, so a partial pass — a profile update
        // that landed beside a plan that was refused — still tells the coach
        // what did change. A refusal changes nothing, and reports nothing here.
        if applied { await onApplied?() }
    }

    /// What to put in front of the lifter when something could not be taken in.
    ///
    /// **A refusal is written to whoever wrote the document, and the lifter is
    /// not him.** "Send it under a key the format has" and "unknown key
    /// `dropSets` at weeks → 0 → days → 1" are exactly right for Claude and
    /// useless in an alert on a phone: the person reading it cannot rewrite the
    /// plan, and nothing tells him what he *can* do. So a refusal reaches him
    /// as two sentences — what happened, in terms of his training, and the one
    /// thing that fixes it — with the author's own sentence kept underneath,
    /// unaltered, because relaying it is the fix. Nothing is summarized away:
    /// the detail he shows Claude is the detail Claude was given.
    ///
    /// Anything that is not a refusal of a document — a folder that cannot be
    /// reached, a file that is not JSON — is shown as it is. Those are already
    /// about the phone rather than about the plan.
    private static func describe(_ error: any Error) -> String {
        guard let addressedToTheAuthor = Self.authorFacingMessage(of: error) else {
            return (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return """
            Claude sent a plan this app could not read whole, so none of it was taken in. \
            Nothing you have already logged has changed. Ask him to send it again — showing \
            him what it says below is the quickest fix, and he will know what to do with it.

            \(addressedToTheAuthor)
            """
    }

    /// The sentence a refusal addresses to whoever wrote the document, or `nil`
    /// when the failure was not about a document's contents at all.
    ///
    /// The two cases are the two ways a document is turned away: refused while
    /// being read, by the rule both clients share, or refused on import for
    /// naming an exercise that does not exist.
    private static func authorFacingMessage(of error: any Error) -> String? {
        switch error {
        case let refusal as DocumentRefusal: refusal.message
        case let failure as PlanImportError: failure.errorDescription
        default: nil
        }
    }

    private static func deduplicated(_ messages: [String]) -> [String] {
        var seen: Set<String> = []
        return messages.filter { seen.insert($0).inserted }
    }

    /// Resolves the iCloud container and reads the plan, off the main actor.
    ///
    /// Detached rather than a plain `async` call: whether a `nonisolated async`
    /// function leaves the caller's actor depends on the language mode in
    /// force, and this must leave it under every one of them.
    private static func readPlan(
        from transport: any DocumentTransport
    ) async throws -> PlanDocument? {
        try await Task.detached { try transport.readPlan() }.value
    }

    /// The same, for the other document. Off the main actor for the same
    /// reason: it reaches the same container resolution.
    private static func readProfileUpdate(
        from transport: any DocumentTransport
    ) async throws -> ProfileUpdate? {
        try await Task.detached { try transport.readProfileUpdate() }.value
    }
}

extension String {
    /// The string, or `nil` when there is nothing in it. An empty error message
    /// would put an empty alert on screen.
    fileprivate var nilWhenEmpty: String? { isEmpty ? nil : self }
}
