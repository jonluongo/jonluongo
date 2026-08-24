import Foundation
import LiftingKit

extension ToolRunner {

    /// How many movements come back when the coach does not say.
    ///
    /// **Stated once, and the schema interpolates it.** The description used to
    /// carry the number as prose — *"Defaults to 50"* — beside code that applied
    /// no default at all, which is the same drift that had `write_plan`
    /// advertising a string where a number was required. A published number the
    /// code does not honour is worse than none.
    static let defaultExerciseLimit = 50

    /// The catalog, so a plan can be written in IDs the app will accept.
    ///
    /// **It subtracts nothing.** It used to remove what the user avoided,
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

        // **A word the catalog does not use is refused, not answered with
        // nothing.** `count: 0` reads as *no exercise trains that*, so a coach
        // who typed `quads` narrows, finds an empty catalog, and plans around a
        // gap that is a spelling mistake. The schema publishes these values, but
        // a schema is advice a client may not enforce; this is the refusal.
        let vocabulary = CatalogVocabulary(catalog)
        for (name, given, known) in [
            ("muscle", muscle?.rawValue, vocabulary.muscles.map(\.rawValue)),
            ("equipment", equipment?.rawValue, vocabulary.equipment.map(\.rawValue)),
            ("pattern", pattern?.rawValue, vocabulary.patterns.map(\.rawValue)),
        ] {
            guard let given, !known.contains(given) else { continue }
            return .failure(
                "'\(given)' is not a \(name) this catalog uses, so nothing could match it "
                    + "— which is different from nothing training it. The \(name) values are: "
                    + known.joined(separator: ", ") + ".")
        }

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

        // **The limit is read here, and it used to be advertised and ignored.**
        // A coach asking for five got all 412, which is what the argument exists
        // to prevent. `.first` because the sort above is alphabetical and has no
        // interesting end — what saves him is narrowing, which the note says.
        let bounded = BoundedList(
            matches, limit: arguments["limit"]?.intValue ?? Self.defaultExerciseLimit,
            keeping: .first)

        var keys = bounded.report(
            total: "count", items: "exercises",
            narrowing: "Narrow with 'query', 'muscle', 'equipment' or 'pattern', "
                + "or raise 'limit'.",
            entry: Self.entry)
        keys["catalogVersion"] = .integer(catalog.version)
        return .report(.object(keys))
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
