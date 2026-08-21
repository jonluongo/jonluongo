import Foundation
import LiftingKit

extension ToolRunner {

    /// The catalog, so a plan can be written in IDs the app will accept.
    ///
    /// **It subtracts nothing.** It used to remove what the lifter avoided,
    /// which is prose in `ACCOUNT.md` now — and hiding a movement was the wrong
    /// answer anyway. A coach who reads *left knee, since June* and sees the
    /// squat still listed has more to work with than one handed a shorter list
    /// with no explanation, and prose carries degrees — *avoid unless nothing
    /// else works*, *avoid until it settles* — that a filtered list cannot.
    func listExercises(_ arguments: JSONValue) -> ToolOutcome {
        let query = arguments["query"]?.stringValue?.lowercased()
        let pattern = arguments["pattern"]?.stringValue.map { MovementPattern(rawValue: $0) }
        let equipment = arguments["equipment"]?.stringValue.map { EquipmentType(rawValue: $0) }
        let muscle = arguments["muscle"]?.stringValue.map { MuscleGroup(rawValue: $0) }

        var filter = ExerciseFilter()
        if let pattern { filter.patterns = [pattern] }
        if let equipment { filter.equipment = [equipment] }
        if let muscle { filter.muscles = [muscle] }
        var matches = catalog.exercises(matching: filter)
        if let query, !query.isEmpty {
            matches = matches.filter {
                $0.displayName.lowercased().contains(query) || $0.id.rawValue.contains(query)
            }
        }
        matches.sort { $0.id.rawValue < $1.id.rawValue }

        return .report([
            "catalogVersion": .integer(catalog.version),
            "count": .integer(matches.count),
            "exercises": .array(matches.map(Self.entry)),
        ])
    }

    private static func entry(_ exercise: Exercise) -> JSONValue {
        .object([
            "id": .string(exercise.id.rawValue),
            "displayName": .string(exercise.displayName),
            "pattern": .string(exercise.pattern.rawValue),
            "equipment": .string(exercise.equipment.rawValue),
            "primaryMuscles": .array(exercise.primaryMuscles.map { .string($0.rawValue) }),
        ])
    }
}
