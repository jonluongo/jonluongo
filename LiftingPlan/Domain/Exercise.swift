import Foundation

/// The stable identity of an exercise.
///
/// The raw value is the MoveKit slug (`barbell-bench-press`), which is what
/// makes their animation files drop in without a mapping layer. Treat it as an
/// opaque key: never parse it, never display it. Depends on: Foundation only.
struct ExerciseID: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

/// One entry in the bundled exercise catalog.
///
/// Read these from `ExerciseCatalogProviding` rather than constructing them,
/// except in tests. Instances are immutable reference data: they ship with the
/// app, are never written at runtime, and are never persisted to the user's
/// database — user records store an `ExerciseID` instead.
///
/// Decoding is deliberately lenient. Absent collections default to empty and
/// unknown keys are ignored, so a catalog produced by a newer build still loads
/// in an older one. Only `id`, `displayName`, `primaryMuscles`, `equipment`,
/// `pattern`, and `category` are required.
///
/// Depends on: the taxonomies in `Taxonomies.swift`.
struct Exercise: Codable, Hashable, Sendable, Identifiable {

    let id: ExerciseID
    let displayName: String
    /// Alternate names, used by `ExerciseResolver` and search.
    let aliases: [String]
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let equipment: EquipmentType
    let pattern: MovementPattern
    let force: ForceType?
    let mechanic: Mechanic?
    let category: ExerciseCategory
    let instructions: [String]
    /// Bundle filename of a demonstration animation, or `nil` when none ships.
    let mediaAsset: String?

    init(
        id: ExerciseID,
        displayName: String,
        aliases: [String] = [],
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: EquipmentType,
        pattern: MovementPattern,
        force: ForceType? = nil,
        mechanic: Mechanic? = nil,
        category: ExerciseCategory,
        instructions: [String] = [],
        mediaAsset: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.pattern = pattern
        self.force = force
        self.mechanic = mechanic
        self.category = category
        self.instructions = instructions
        self.mediaAsset = mediaAsset
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(ExerciseID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            primaryMuscles: try container.decode([MuscleGroup].self, forKey: .primaryMuscles),
            secondaryMuscles: try container.decodeIfPresent([MuscleGroup].self, forKey: .secondaryMuscles) ?? [],
            equipment: try container.decode(EquipmentType.self, forKey: .equipment),
            pattern: try container.decode(MovementPattern.self, forKey: .pattern),
            force: try container.decodeIfPresent(ForceType.self, forKey: .force),
            mechanic: try container.decodeIfPresent(Mechanic.self, forKey: .mechanic),
            category: try container.decode(ExerciseCategory.self, forKey: .category),
            instructions: try container.decodeIfPresent([String].self, forKey: .instructions) ?? [],
            mediaAsset: try container.decodeIfPresent(String.self, forKey: .mediaAsset)
        )
    }

    /// Lowercased haystack of the display name and every alias, for search and
    /// resolution.
    var searchText: String {
        ([displayName] + aliases).joined(separator: " ").lowercased()
    }

    /// Whether this is resistance training, as opposed to cardio or stretching.
    var isResistanceTraining: Bool {
        ExerciseCategory.resistance.contains(category)
    }
}
