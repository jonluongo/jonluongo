import Foundation
import SwiftData
import LiftingKit

/// Turns the stored graph into a `TrainingSnapshot`.
///
/// **What it does.** Reads every session and every performance out of the store
/// and states them as plain values the macOS server can read. It is the outbound
/// half of the loop: the coach reads this and writes a plan back.
///
/// **It fetches rather than walking relationships.** A relationship read returns
/// what the context happens to have faulted in, which is why a snapshot could
/// once report four sessions of a block that holds nine. Two fetches, no
/// traversal from a root, nothing filtered.
///
/// **Every prescription is stated once**, through
/// `PlanDocumentSession(reconstructing:)` — the document the coach wrote, not a
/// second description of it.
///
/// **What it depends on.** `TrainingSnapshot` from LiftingKit, the `Store/`
/// models, and a `ModelContext`. It reads and never writes, and it concludes
/// nothing about training.
enum SnapshotExporter {

    /// The whole record, as of now.
    ///
    /// `exportedAt` is the caller's clock rather than this function's, so a test
    /// can state the instant and the app can state the moment it wrote the file.
    /// - Parameter refused: the plan the phone last turned away, if one stands.
    ///   **It is not read out of the store, because it is not part of the
    ///   record** — nothing was taken in, so there is nothing in the store to
    ///   find. It is the phone's answer about a document, carried here so the
    ///   coach hears it; see `RefusalRecord`.
    static func export(
        from context: ModelContext,
        catalogVersion: Int,
        exportedAt: Date = Date(),
        refused: SnapshotRefusal? = nil
    ) throws -> TrainingSnapshot {
        TrainingSnapshot(
            exportedAt: exportedAt,
            catalogVersion: catalogVersion,
            sessions: try context.fetch(FetchDescriptor<Session>()).map(snapshot(of:)),
            performances: try context.fetch(FetchDescriptor<PerformedExercise>())
                .map(snapshot(of:)),
            refused: refused)
    }

    /// One session: what was prescribed, and the two facts the store adds.
    private static func snapshot(of session: Session) -> SnapshotSession {
        SnapshotSession(
            prescription: PlanDocumentSession(reconstructing: session),
            finishedAt: session.finishedAt,
            generatedAt: session.generatedAt,
            sourceDocumentID: session.sourceDocumentID)
    }

    /// One performance, carrying its own coordinates.
    ///
    /// The coordinates are copied rather than linked so the record stays
    /// readable with no session behind it — a log that stops making sense when a
    /// plan is deleted is not a log. A stated baseline has none, and that is the
    /// honest answer rather than a zero.
    private static func snapshot(of performed: PerformedExercise) -> SnapshotPerformedExercise {
        SnapshotPerformedExercise(
            exerciseID: performed.exerciseID,
            occurredAt: performed.occurredAt,
            source: performed.source,
            blockOrdinal: performed.session?.blockOrdinal,
            sessionOrdinal: performed.session?.ordinal,
            userNote: performed.userNote,
            sets: performed.orderedSets.map(snapshot(of:)))
    }

    /// One set, exactly as it was recorded. No measure is converted into
    /// another, and an absent one stays absent.
    private static func snapshot(of set: PerformedSet) -> SnapshotPerformedSet {
        SnapshotPerformedSet(
            setIndex: set.setIndex,
            isWarmup: set.isWarmup,
            load: set.load,
            work: set.work,
            completedAt: set.completedAt)
    }
}
