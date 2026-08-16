import Foundation

/// The stable identity of an exercise.
///
/// The raw value is the MoveKit slug (`barbell-bench-press`), which is what
/// makes their animation files drop in without a mapping layer. Treat it as an
/// opaque key: never parse it, never display it. Depends on: Foundation only.
public struct ExerciseID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// One entry in the bundled exercise catalog.
///
/// Read these from `ExerciseCatalogProviding`; there is no public initializer,
/// so an entry outside the catalog cannot be minted. Instances are immutable
/// reference data: they ship inside this package, are never written at runtime,
/// and are never persisted to the user's database — user records store an
/// `ExerciseID` instead.
///
/// Decoding is deliberately lenient. Absent collections default to empty and
/// unknown keys are ignored, so a catalog produced by a newer build still loads
/// in an older one. Only `id`, `displayName`, `primaryMuscles`, `equipment`,
/// `pattern`, and `category` are required.
///
/// Depends on: the taxonomies in `Taxonomies.swift`.
public struct Exercise: Codable, Hashable, Sendable, Identifiable {

    public let id: ExerciseID
    public let displayName: String
    /// Alternate names, used by `ExerciseResolver` and search.
    public let aliases: [String]
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let equipment: EquipmentType
    public let pattern: MovementPattern
    public let force: ForceType?
    public let mechanic: Mechanic?
    public let category: ExerciseCategory
    public let instructions: [String]
    /// Bundle filename of a demonstration animation, or `nil` when none ships.
    public let mediaAsset: String?
    /// How much training experience the movement asks for. `nil` when the
    /// catalog entry did not grade it — an entry that says nothing about how
    /// hard a movement is has not said it is of middling difficulty, and a
    /// reader choosing exercises for a beginner must be able to tell those
    /// apart.
    public let difficulty: Difficulty?

    /// Internal by design: outside this package an `Exercise` comes from the
    /// catalog or from decoding `exercises.json`, never from a literal, so a
    /// client cannot mint an entry the catalog does not have.
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
        mediaAsset: String? = nil,
        difficulty: Difficulty? = nil
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
        self.difficulty = difficulty
    }

    public init(from decoder: any Decoder) throws {
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
            mediaAsset: try container.decodeIfPresent(String.self, forKey: .mediaAsset),
            difficulty: try container.decodeIfPresent(Difficulty.self, forKey: .difficulty)
        )
    }

    /// Lowercased haystack of the display name and every alias, for search and
    /// resolution. Internal: it exists to serve `ExerciseCatalog.search`, and
    /// no client of this package reads it.
    var searchText: String {
        ([displayName] + aliases).joined(separator: " ").lowercased()
    }

    /// Whether this is resistance training, as opposed to cardio or stretching.
    /// Internal until a client needs it; `ExerciseFilter(categories:)` is the
    /// public way to ask the same question of the catalog.
    var isResistanceTraining: Bool {
        ExerciseCategory.resistance.contains(category)
    }
}
