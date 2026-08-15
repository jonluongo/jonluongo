import Foundation
import LiftingKit

extension ToolRunner {

    /// Catalog entries with their real IDs, narrowed to what this lifter can
    /// actually perform.
    ///
    /// This is what makes a hallucinated exercise ID impossible in normal use:
    /// Claude picks an entry from here rather than typing a name. Each entry
    /// carries enough — name, pattern, equipment, both muscle lists, mechanic,
    /// difficulty — to choose well without a second call.
    ///
    /// The narrowing is reported alongside the results in `appliedFilter`, and
    /// `includeUnavailable` turns it off, so "the lifter cannot do this" is
    /// never indistinguishable from "the catalog does not have this". A lifter
    /// with no profile yet is narrowed by nothing, and the report says so.
    func listExercises(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        let requested = ExerciseFilter(
            equipment: Set((arguments.strings(at: "equipment") ?? []).map(EquipmentType.init)),
            patterns: Set((arguments.strings(at: "pattern") ?? []).map(MovementPattern.init)),
            muscles: Set((arguments.strings(at: "muscle") ?? []).map(MuscleGroup.init))
        )
        let query = arguments["query"]?.stringValue
        let narrowToLifter = arguments["includeUnavailable"]?.boolValue != true
        let profile = narrowToLifter ? snapshot.profile : nil

        var matches = query.map { catalog.search($0, limit: catalog.all.count) } ?? catalog.all
        matches = matches.filter(requested.matches)
        if let profile {
            let available = Set(profile.availableEquipment)
            let avoidedPatterns = Set(profile.avoidedPatterns)
            let avoidedExercises = Set(profile.avoidedExercises)
            matches = matches.filter {
                available.contains($0.equipment)
                    && !avoidedPatterns.contains($0.pattern)
                    && !avoidedExercises.contains($0.id)
            }
        }

        let limit = arguments["limit"]?.intValue ?? Self.defaultExerciseLimit
        return .report([
            "count": .integer(min(limit, matches.count)),
            "totalMatching": .integer(matches.count),
            "limit": .integer(limit),
            "catalogVersion": .integer(catalog.version),
            "appliedFilter": appliedFilter(arguments, requested: requested, profile: profile),
            "note": .string(narrowingNote(snapshot: snapshot, narrowed: narrowToLifter)),
            "exercises": .array(matches.prefix(limit).map(Self.entry)),
        ])
    }

    /// How many entries come back when the call does not say. A cap on a
    /// response, not an opinion about training.
    static let defaultExerciseLimit = 50

    /// One catalog entry, complete enough to choose a movement from without a
    /// second call.
    private static func entry(_ exercise: Exercise) -> JSONValue {
        [
            "id": .string(exercise.id.rawValue),
            "name": .string(exercise.displayName),
            "pattern": .string(exercise.pattern.rawValue),
            "equipment": .string(exercise.equipment.rawValue),
            "primaryMuscles": .taxonomy(exercise.primaryMuscles),
            "secondaryMuscles": .taxonomy(exercise.secondaryMuscles),
            "mechanic": .string(exercise.mechanic?.rawValue),
            "force": .string(exercise.force?.rawValue),
            "category": .string(exercise.category.rawValue),
            "difficulty": .string(exercise.difficulty.rawValue),
            "aliases": .array(exercise.aliases.map { .string($0) }),
        ]
    }

    /// Everything that narrowed this answer, stated rather than applied
    /// silently. A result that was filtered without saying so is a result that
    /// cannot be reasoned about.
    private func appliedFilter(
        _ arguments: JSONValue, requested: ExerciseFilter, profile: SnapshotProfile?
    ) -> JSONValue {
        [
            "query": .string(arguments["query"]?.stringValue),
            "pattern": .taxonomy(Self.ordered(requested.patterns)),
            "muscle": .taxonomy(Self.ordered(requested.muscles)),
            "equipment": .taxonomy(Self.ordered(requested.equipment)),
            "lifterEquipment": profile.map { .taxonomy($0.availableEquipment) } ?? .null,
            "avoidedPatterns": profile.map { .taxonomy($0.avoidedPatterns) } ?? .null,
            "avoidedExercises": profile.map {
                .array($0.avoidedExercises.map { .string($0.rawValue) })
            } ?? .null,
        ]
    }

    /// A set in a stable order, so the same call twice reads the same twice.
    private static func ordered<T: ExtensibleTaxonomy>(_ values: Set<T>) -> [T] {
        values.sorted { $0.rawValue < $1.rawValue }
    }

    private func narrowingNote(snapshot: TrainingSnapshot, narrowed: Bool) -> String {
        guard narrowed else {
            return "Nothing was narrowed: includeUnavailable was set, so this is the whole "
                + "catalog including movements the lifter said he avoids or has no equipment for."
        }
        guard snapshot.profile != nil else {
            return "This lifter has not been set up yet, so nothing is known about his equipment "
                + "or what he avoids and nothing was narrowed. Every entry here is in the "
                + "catalog; not all of them are necessarily ones he can perform."
        }
        return "Narrowed to what this lifter can perform — see appliedFilter. Pass "
            + "includeUnavailable to see what was left out. Use these IDs verbatim in write_plan."
    }
}
