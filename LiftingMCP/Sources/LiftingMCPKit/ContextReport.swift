import Foundation
import LiftingKit

/// The compact context that rides along on every turn: when the record was
/// written, where the user is in it, and what he did lately.
///
/// **Who he is is not in here any more.** It used to carry his goal, experience,
/// constraints, equipment, avoid lists, bodyweight and every strength baseline —
/// nine fields, each one display-only in the app. They are prose in `ACCOUNT.md`
/// now, which the coach reads as a resource and writes with `update_notes`.
/// A paragraph he wrote says more than nine fields he had to fit into.
///
/// **`exportedAt` leads, and the age beside it.** The failure this exists to
/// prevent arrives looking like a fact: a coach told a block holds four sessions
/// when it holds nine. The phone is the only writer of the record and exports
/// whenever it changes, so a stale read means the app has not been opened — and
/// that is worth knowing before anything else here is believed.
///
/// **It concludes nothing.** No readiness score, no verdict on whether a lift is
/// stalling, no assessment of balance. Those are the coach's to draw.
///
/// **It is deliberately small** — small enough to carry constantly — which is
/// what makes the drill-down tools worth having: depth is paid for only when it
/// is wanted, and `note` says where to go for it.
///
/// Depends on: `ToolRunner`, `TrainingLog`, and the snapshot value types.
struct ContextReport {

    let runner: ToolRunner
    let snapshot: TrainingSnapshot

    /// How many recent sessions ride along before the tools take over.
    static let carriedSessions = 5

    func build() -> JSONValue {
        let sessions = TrainingLog.sessions(in: snapshot)
        let trained = TrainingLog.trained(in: snapshot)

        return [
            "exportedAt": .date(snapshot.exportedAt),
            "recordAgeDays": .integer(ageInDays),
            "catalogVersion": .integer(snapshot.catalogVersion),
            "user": .object([
                "note": .string(
                    "Who he is, what he trains for, his injuries, his equipment and his "
                        + "bodyweight are in ACCOUNT.md. Read it as a resource; write to it with "
                        + "update_notes.")
            ]),
            "programme": .object([
                "note": .string(
                    "Why this programme — the approach, what is being progressed, what makes "
                        + "a block a deload — is in PROGRAM.md.")
            ]),
            "where": whereHeIs(sessions),
            "sessionsRecorded": .integer(trained.count),
            "recent": .array(trained.prefix(Self.carriedSessions).map(Self.summary)),
            "note": .string(
                "This is a summary. \(ToolCatalog.exerciseHistory) reports every performance "
                    + "of one movement with what was prescribed beside it; "
                    + "\(ToolCatalog.recentSessions) reports whole sessions; "
                    + "\(ToolCatalog.volumeByMuscle) totals recent work."),
        ]
    }

    /// How old the record is, in whole days.
    ///
    /// Reported rather than judged: whether four days is stale depends on how
    /// often he trains, which is not this server's call.
    private var ageInDays: Int {
        max(0, Calendar(identifier: .gregorian).dateComponents(
            [.day], from: snapshot.exportedAt, to: runner.now()).day ?? 0)
    }

    /// The session he is on, and what is left ahead of it.
    ///
    /// **`nil` when he has finished everything prescribed**, which is the
    /// truthful answer on that day rather than a gap to be filled — and it is
    /// the cue that the next block is due.
    private func whereHeIs(_ sessions: [SessionRecord]) -> JSONValue {
        let next = sessions.first { !$0.wasTrained }
        return .object([
            "blocksPrescribed": .integer(Set(sessions.map(\.blockOrdinal)).count),
            "sessionsPrescribed": .integer(sessions.count),
            "currentBlockOrdinal": next.map { .integer($0.blockOrdinal) } ?? .null,
            "currentSessionOrdinal": next.map { .integer($0.ordinal) } ?? .null,
            "currentSessionFocus": next.map { .string($0.focus) } ?? .null,
            "nothingPrescribedBeyond": .bool(next == nil),
        ])
    }

    /// One session, said in a line: when, where, and what was done.
    private static func summary(_ record: SessionRecord) -> JSONValue {
        .object([
            "blockOrdinal": .integer(record.blockOrdinal),
            "ordinal": .integer(record.ordinal),
            "focus": .string(record.focus),
            "occurredAt": record.occurredAt.map { .date($0) } ?? .null,
            "finished": .bool(record.isFinished),
            "movements": .integer(record.performances.count),
            "setsPerformed": .integer(record.performedSets.count),
        ])
    }
}
