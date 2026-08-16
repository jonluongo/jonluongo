import Foundation
import LiftingKit

/// What a tool answered.
///
/// A `report` is data Claude asked for. A `failure` is a sentence Claude can
/// act on — a bad exercise ID, a snapshot that is not there yet — carried back
/// as a tool result rather than a JSON-RPC error so the model reads it and
/// corrects itself instead of the client swallowing it.
///
/// Depends on: `JSONValue`.
public enum ToolOutcome: Sendable, Hashable {
    case report(JSONValue)
    case failure(String)
}

/// Runs one MCP tool call and hands back what it found.
///
/// Build one with the shared folder, the bundled catalog, and a clock, then
/// call `call(_:arguments:)`. Every tool here *reports*: it says what the
/// catalog contains, what was logged, and what was written. **None of them
/// concludes anything about training** — there is deliberately no tool that
/// suggests a progression or returns a verdict on a lifter's balance, because
/// deciding what to do about the data is Claude's job and the reason this
/// server exists.
///
/// The snapshot is read fresh on every call and never cached. A cached snapshot
/// would go stale exactly when the lifter has just trained, which is the moment
/// it matters most.
///
/// Depends on: `TrainingDocuments`, `ExerciseCatalogProviding` from
/// `LiftingKit`, and the report builders in this module.
public struct ToolRunner: Sendable {

    let documents: any TrainingDocuments
    let catalog: any ExerciseCatalogProviding
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - documents: the shared folder, or a stand-in.
    ///   - catalog: the bundled exercise catalog.
    ///   - now: the clock. Injected so a volume window is testable without
    ///     waiting a week.
    public init(
        documents: any TrainingDocuments,
        catalog: any ExerciseCatalogProviding,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.documents = documents
        self.catalog = catalog
        self.now = now
    }

    /// Runs the named tool. An unknown name is a failure naming the tools that
    /// do exist, rather than an empty result that would look like no data.
    public func call(_ name: String, arguments: JSONValue) -> ToolOutcome {
        switch name {
        case ToolCatalog.listExercises: withSnapshot { listExercises(arguments, in: $0) }
        case ToolCatalog.exerciseHistory: withSnapshot { exerciseHistory(arguments, in: $0) }
        case ToolCatalog.recentSessions: withSnapshot { recentSessions(arguments, in: $0) }
        case ToolCatalog.volumeByMuscle: withSnapshot { volumeByMuscle(arguments, in: $0) }
        case ToolCatalog.writePlan: writePlan(arguments)
        // The only two tools that do not read the snapshot: both write into
        // the shared folder, and neither has anything to ask the log.
        case ToolCatalog.updateProfile: updateProfile(arguments)
        default:
            .failure(
                "There is no tool called '\(name)'. This server offers: "
                    + ToolCatalog.definitions.map(\.name).joined(separator: ", ") + "."
            )
        }
    }

    /// The always-present context resource: who the lifter is, what he has to
    /// train with, what block he is on, what he did lately, and what he is
    /// currently working with on each lift.
    public func contextResource() -> ToolOutcome {
        withSnapshot { .report(ContextReport(runner: self, snapshot: $0).build()) }
    }

    // MARK: - The one precondition every tool shares

    /// Reads the snapshot and runs `body` against it, or explains why it could
    /// not.
    ///
    /// This is where the owner's first run lands. A snapshot that is not there
    /// must never read as a lifter with no history — an empty answer looks like
    /// data, and a coach given empty data will confidently plan for a beginner.
    func withSnapshot(_ body: (TrainingSnapshot) -> ToolOutcome) -> ToolOutcome {
        do {
            guard let snapshot = try documents.readSnapshot() else {
                return .failure(Self.noSnapshotYet(at: documents.snapshotLocation))
            }
            return body(snapshot)
        } catch {
            return .failure(
                "The snapshot at \(documents.snapshotLocation) could not be read: "
                    + "\(error.localizedDescription) It is there but unreadable, which is "
                    + "different from missing — do not treat this as a lifter with no history."
            )
        }
    }

    /// The message the owner will see the very first time he tries this.
    ///
    /// It says what is missing, the one action that produces it, where the
    /// server looked, and how to point it somewhere else — because every one of
    /// those is a thing he would otherwise have to guess.
    static func noSnapshotYet(at location: String) -> String {
        """
        No training snapshot yet, so there is nothing to report on. This is not \
        a lifter with no history — it is a file that has not been written.

        LiftingPlan writes snapshot.json when the app moves to the background. \
        On your iPhone: open LiftingPlan, then swipe up to the Home Screen and \
        wait a few seconds for iCloud to sync. Then try again.

        Looked for: \(location)

        If that is the wrong folder, launch the server with \
        `\(ServerConfiguration.directoryArgument) /path/to/folder` or set \
        \(ServerConfiguration.directoryEnvironmentKey) to the folder holding \
        snapshot.json.
        """
    }
}
