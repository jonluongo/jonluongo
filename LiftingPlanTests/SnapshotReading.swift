import Foundation
import LiftingKit

/// Reading a snapshot the way these suites ask about one.
///
/// The wire carries a block as the document the coach wrote and the work against
/// it as a flat series, which is the right shape for a reader and a long walk
/// for a test: `snapshot.routines.first?.document.weeks.first?.days.first?` is
/// four optionals before the assertion starts. These name the walk once.
///
/// Test support only — nothing in the app reads a snapshot at all. It writes
/// them.
extension TrainingSnapshot {

    /// The one block a fixture usually has.
    var firstDocument: PlanDocument? { routines.first?.document }

    /// The first day of the first week of that block.
    var firstDay: PlanDocumentDay? { firstDocument?.weeks.first?.days.first }

    /// The day's movements in prescribed order, groups flattened into the
    /// sequence they are performed in.
    var firstDayExercises: [PlanDocumentExercise] {
        firstDay?.entries.flatMap(\.exercises) ?? []
    }

    /// The first movement that day prescribes.
    var firstPrescribedExercise: PlanDocumentExercise? { firstDayExercises.first }

    /// The earliest set in the log, which is where a fixture with one set puts
    /// it.
    var firstLoggedSet: LoggedSetRecord? {
        log.min { $0.completedAt < $1.completedAt }
    }

    /// Everything logged against one movement, in the order it was logged.
    func loggedSets(of exerciseID: ExerciseID) -> [LoggedSetRecord] {
        log.filter { $0.exerciseID == exerciseID }
            .sorted { $0.setIndex < $1.setIndex }
    }
}
