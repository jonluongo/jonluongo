import Foundation
import LiftingKit

/// Whose clock the rest sheet is editing: one exercise's, or one group's.
///
/// The sheet asks the same question either way — follow the plan, run this long,
/// or run nothing — so it takes one value rather than being written twice. A
/// group's choice is keyed on the exercise its round ends with, which is the
/// exercise that carries the group's rest.
struct RestTarget: Identifiable {
    let id: String
    let name: String
    let prescribedSeconds: Int?
    let key: ExerciseID

    init(exercise: PlannedExercise) {
        id = "exercise-\(exercise.persistentModelID)"
        name = exercise.exerciseID.rawValue
        prescribedSeconds = exercise.restSeconds
        key = exercise.exerciseID
    }

    /// `nil` for a group whose members somehow arrived without one, which the
    /// format cannot state and no screen should crash over.
    init?(group: ExerciseGroup) {
        guard let key = group.restKey else { return nil }
        id = "group-\(group.ordinal)"
        name = "Round \(group.letter)"
        prescribedSeconds = group.restSeconds
        self.key = key
    }
}
