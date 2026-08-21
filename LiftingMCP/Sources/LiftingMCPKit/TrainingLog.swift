import Foundation
import LiftingKit

/// One session the coach can read: what was prescribed, and what was done.
///
/// **It used to be assembled and is now just joined.** The log was a flat series
/// of sets keyed by routine, block and weekday, so reading a session meant
/// grouping every set by a composite key, finding the routine it belonged to,
/// finding the block inside that routine's document, and then the day inside
/// that block. The record carries sessions and performances directly now, each
/// stating its own coordinates, so this pairs two lists.
///
/// **What it depends on.** `SnapshotSession` and `SnapshotPerformedExercise`
/// from LiftingKit. It reports and concludes nothing.
struct SessionRecord: Sendable {

    /// What the coach prescribed, and whether the user finished it.
    let session: SnapshotSession
    /// What he actually did in it, one entry per movement.
    let performances: [SnapshotPerformedExercise]

    var blockOrdinal: Int { session.blockOrdinal }
    var ordinal: Int { session.ordinal }
    var focus: String { session.prescription.focus }
    var isFinished: Bool { session.isFinished }

    /// The movements prescribed, groups flattened into the order they are
    /// trained.
    var prescribed: [PlanDocumentExercise] { session.prescription.exercises }

    /// When this was trained, or `nil` if it has not been.
    ///
    /// The earliest performance rather than the moment Finish was pressed: a
    /// session finished days later is still training that happened when it
    /// happened.
    var occurredAt: Date? { performances.map(\.occurredAt).min() }

    /// Whether anything happened here at all. A session he finished without
    /// recording a set counts — he went through it.
    var wasTrained: Bool { !performances.isEmpty || isFinished }

    /// Every set performed, in the order it happened.
    var performedSets: [SnapshotPerformedSet] {
        performances.flatMap(\.sets).sorted { $0.completedAt < $1.completedAt }
    }
}

/// Reading the record the app wrote.
///
/// **What it does.** Pairs each prescribed session with what was performed
/// against it, and answers the two questions every report starts from: which
/// sessions are there, and which of them were trained.
///
/// **What it depends on.** `TrainingSnapshot`. It never writes and never judges:
/// whether a lift is progressing is the coach's to say, and this only hands him
/// what happened.
enum TrainingLog {

    /// Every session the record holds, in the order they are to be trained.
    static func sessions(in snapshot: TrainingSnapshot) -> [SessionRecord] {
        let byCoordinates = Dictionary(grouping: snapshot.performances) {
            Coordinates(block: $0.blockOrdinal, ordinal: $0.sessionOrdinal)
        }
        return snapshot.sessions
            .sorted { ($0.blockOrdinal, $0.ordinal) < ($1.blockOrdinal, $1.ordinal) }
            .map { session in
                SessionRecord(
                    session: session,
                    performances: byCoordinates[
                        Coordinates(block: session.blockOrdinal, ordinal: session.ordinal)
                    ] ?? [])
            }
    }

    /// The sessions that actually happened, most recent first.
    ///
    /// **A session prescribed and never trained is not a session.** Reporting it
    /// as one would tell the coach a user trained on a day he did not.
    static func trained(in snapshot: TrainingSnapshot) -> [SessionRecord] {
        sessions(in: snapshot)
            .filter(\.wasTrained)
            .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }

    /// Every performance of one movement, oldest first — including a baseline he
    /// stated rather than logged, which has no session behind it.
    static func history(
        of exerciseID: ExerciseID, in snapshot: TrainingSnapshot
    ) -> [SnapshotPerformedExercise] {
        snapshot.performances(of: exerciseID)
    }

    /// Where a performance sits. A stated baseline has no session, and `nil`
    /// groups with `nil` rather than with block 1.
    private struct Coordinates: Hashable {
        let block: Int?
        let ordinal: Int?
    }
}
