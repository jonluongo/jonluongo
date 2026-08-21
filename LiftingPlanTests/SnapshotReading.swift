import Foundation
import LiftingKit

/// Reading a snapshot the way these suites ask about one.
///
/// The wire carries a session as the document the coach wrote and the work
/// against it as performances, which is the right shape for a reader and a long
/// walk for a test. These name the walk once.
///
/// **It got shorter with the format.** A block used to be four optionals deep —
/// `routines.first?.document.blocks.first?.days.first?` — because a snapshot
/// held routines holding documents holding blocks holding days. Sessions are a
/// flat list now, so the first one is the first one.
///
/// Test support only: nothing in the app reads a snapshot. It writes them.
extension TrainingSnapshot {

    /// The first session the record holds.
    var firstSession: SnapshotSession? { sessions.first }

    /// What that session prescribed.
    var firstPrescription: PlanDocumentSession? { firstSession?.prescription }

    /// The session's movements in prescribed order, groups flattened into the
    /// sequence they are performed in.
    var firstSessionExercises: [PlanDocumentExercise] {
        firstPrescription?.exercises ?? []
    }

    /// The first movement that session prescribes.
    var firstPrescribedExercise: PlanDocumentExercise? { firstSessionExercises.first }

    /// The earliest performance in the record, which is where a fixture with one
    /// set puts it.
    var firstPerformance: SnapshotPerformedExercise? {
        performances.min { $0.occurredAt < $1.occurredAt }
    }

    /// The earliest set performed.
    var firstPerformedSet: SnapshotPerformedSet? {
        firstPerformance?.sets.min { $0.completedAt < $1.completedAt }
    }
}
